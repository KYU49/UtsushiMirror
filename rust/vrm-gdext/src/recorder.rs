use std::io::Write;
use std::path::Path;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, SyncSender};
use std::thread::JoinHandle;

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordFormat {
    Mp4,
    WebmAlpha,
}

impl RecordFormat {
    pub fn from_str(s: &str) -> Self {
        match s {
            "webm_alpha" | "webm" => Self::WebmAlpha,
            _ => Self::Mp4,
        }
    }
}

pub struct FfmpegRecorder {
    width: u32,
    height: u32,
    output_path: String,
    async_tx: Option<SyncSender<Vec<u8>>>,
    async_thread: Option<JoinHandle<Result<(), String>>>,
    sync_child: Option<Child>,
    sync_stdin: Option<ChildStdin>,
    frames_written: u64,
}

impl FfmpegRecorder {
    pub fn start_async(
        output_path: &str,
        width: u32,
        height: u32,
        fps: u32,
        format: RecordFormat,
        audio_path: Option<&str>,
    ) -> Result<Self, String> {
        let mut child = spawn_ffmpeg(output_path, width, height, fps, format, audio_path)?;
        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| "Failed to take ffmpeg stdin".to_string())?;

        let (tx, rx) = mpsc::sync_channel::<Vec<u8>>(8);
        let thread = std::thread::Builder::new()
            .name("vrm-ffmpeg-writer".into())
            .spawn(move || {
                while let Ok(frame) = rx.recv() {
                    if let Err(e) = stdin.write_all(&frame) {
                        drop(stdin);
                        let _ = child.wait();
                        return Err(format!("ffmpeg write error: {e}"));
                    }
                }
                let _ = stdin.flush();
                drop(stdin);
                let status = child
                    .wait()
                    .map_err(|e| format!("ffmpeg wait failed: {e}"))?;
                if !status.success() {
                    return Err(format!("ffmpeg exited with status {status}"));
                }
                Ok(())
            })
            .map_err(|e| format!("spawn ffmpeg writer thread: {e}"))?;

        Ok(Self {
            width,
            height,
            output_path: output_path.to_string(),
            async_tx: Some(tx),
            async_thread: Some(thread),
            sync_child: None,
            sync_stdin: None,
            frames_written: 0,
        })
    }

    pub fn start_sync(
        output_path: &str,
        width: u32,
        height: u32,
        fps: u32,
        format: RecordFormat,
        audio_path: Option<&str>,
    ) -> Result<Self, String> {
        let mut child = spawn_ffmpeg(output_path, width, height, fps, format, audio_path)?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| "Failed to take ffmpeg stdin".to_string())?;
        Ok(Self {
            width,
            height,
            output_path: output_path.to_string(),
            async_tx: None,
            async_thread: None,
            sync_child: Some(child),
            sync_stdin: Some(stdin),
            frames_written: 0,
        })
    }

    pub fn push_frame_async(&mut self, rgba: &[u8]) -> bool {
        let expected = (self.width as usize) * (self.height as usize) * 4;
        if rgba.len() != expected {
            return false;
        }
        if let Some(tx) = &self.async_tx {
            match tx.try_send(rgba.to_vec()) {
                Ok(()) => {
                    self.frames_written += 1;
                    true
                }
                Err(_) => false,
            }
        } else {
            false
        }
    }

    pub fn write_frame_blocking(&mut self, rgba: &[u8]) -> Result<(), String> {
        let expected = (self.width as usize) * (self.height as usize) * 4;
        if rgba.len() != expected {
            return Err(format!(
                "Invalid RGBA frame size: got {}, expected {}",
                rgba.len(),
                expected
            ));
        }
        if let Some(stdin) = &mut self.sync_stdin {
            stdin
                .write_all(rgba)
                .map_err(|e| format!("ffmpeg write failed: {e}"))?;
            self.frames_written += 1;
            Ok(())
        } else {
            Err("Recorder is not in synchronous mode".into())
        }
    }

    pub fn finish(mut self) -> Result<(String, u64), String> {
        let frames = self.frames_written;
        let out = self.output_path.clone();

        if let Some(tx) = self.async_tx.take() {
            drop(tx);
        }
        if let Some(t) = self.async_thread.take() {
            let res = t
                .join()
                .map_err(|_| "ffmpeg writer thread panicked".to_string())?;
            res?;
        }
        if let Some(mut stdin) = self.sync_stdin.take() {
            let _ = stdin.flush();
            drop(stdin);
        }
        if let Some(mut child) = self.sync_child.take() {
            let status = child
                .wait()
                .map_err(|e| format!("ffmpeg wait failed: {e}"))?;
            if !status.success() {
                return Err(format!("ffmpeg exited with status {status}"));
            }
        }
        Ok((out, frames))
    }

    pub fn frames_written(&self) -> u64 {
        self.frames_written
    }

    pub fn output_path(&self) -> &str {
        &self.output_path
    }
}

fn spawn_ffmpeg(
    output_path: &str,
    width: u32,
    height: u32,
    fps: u32,
    format: RecordFormat,
    audio_path: Option<&str>,
) -> Result<Child, String> {
    if let Some(parent) = Path::new(output_path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|e| format!("mkdir {}: {e}", parent.display()))?;
        }
    }

    let size_arg = format!("{width}x{height}");
    let fps_arg = fps.max(1).to_string();

    let mut cmd = Command::new("ffmpeg");
    cmd.args([
        "-y",
        "-loglevel",
        "error",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgba",
        "-s",
        &size_arg,
        "-r",
        &fps_arg,
        "-i",
        "-",
    ]);

    let has_audio = audio_path.is_some_and(|p| !p.trim().is_empty());
    if let Some(aud) = audio_path.filter(|p| !p.trim().is_empty()) {
        cmd.args(["-i", aud]);
    }

    match format {
        RecordFormat::Mp4 => {
            cmd.args([
                "-c:v",
                "libx264",
                "-pix_fmt",
                "yuv420p",
                "-crf",
                "18",
                "-preset",
                "fast",
                "-movflags",
                "+faststart",
            ]);
            if has_audio {
                cmd.args(["-c:a", "aac", "-b:a", "192k", "-shortest"]);
            }
        }
        RecordFormat::WebmAlpha => {
            cmd.args([
                "-c:v",
                "libvpx-vp9",
                "-pix_fmt",
                "yuva420p",
                "-crf",
                "24",
                "-b:v",
                "0",
                "-auto-alt-ref",
                "0",
            ]);
            if has_audio {
                cmd.args(["-c:a", "libopus", "-b:a", "160k", "-shortest"]);
            }
        }
    }

    cmd.arg(output_path);
    cmd.stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit());

    #[cfg(target_os = "windows")]
    {
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }

    cmd.spawn()
        .map_err(|e| format!("Failed to spawn ffmpeg (is ffmpeg in PATH?): {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_mp4_and_webm_alpha_via_ffmpeg() {
        let dir = std::env::temp_dir().join("vrmviewer_rec_test");
        let _ = std::fs::create_dir_all(&dir);
        let mp4_path = dir.join("test_out.mp4");
        let webm_path = dir.join("test_alpha.webm");

        let w = 64u32;
        let h = 64u32;
        let mut frame = vec![0u8; (w * h * 4) as usize];
        for y in 0..h {
            for x in 0..w {
                let idx = ((y * w + x) * 4) as usize;
                frame[idx] = ((x * 4) % 256) as u8;
                frame[idx + 1] = ((y * 4) % 256) as u8;
                frame[idx + 2] = 180;
                frame[idx + 3] = if x > 16 && x < 48 { 255 } else { 0 };
            }
        }

        let mut rec_mp4 =
            FfmpegRecorder::start_sync(mp4_path.to_str().unwrap(), w, h, 30, RecordFormat::Mp4, None)
                .expect("start mp4 recorder");
        for _ in 0..10 {
            rec_mp4.write_frame_blocking(&frame).unwrap();
        }
        let (_, cnt) = rec_mp4.finish().unwrap();
        assert_eq!(cnt, 10);
        assert!(std::fs::metadata(&mp4_path).unwrap().len() > 200);

        let mut rec_webm = FfmpegRecorder::start_sync(
            webm_path.to_str().unwrap(),
            w,
            h,
            30,
            RecordFormat::WebmAlpha,
            None,
        )
        .expect("start webm recorder");
        for _ in 0..10 {
            rec_webm.write_frame_blocking(&frame).unwrap();
        }
        let (_, cnt2) = rec_webm.finish().unwrap();
        assert_eq!(cnt2, 10);
        assert!(std::fs::metadata(&webm_path).unwrap().len() > 200);

        let _ = std::fs::remove_dir_all(&dir);
    }
}
