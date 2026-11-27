use std::io::Write;
use std::path::Path;
use std::process::{Child, ChildStdin, Stdio};
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
        let mut child = spawn_ffmpeg(output_path, width, height, fps, format, audio_path, true)?;
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
        let mut child = spawn_ffmpeg(output_path, width, height, fps, format, audio_path, false)?;
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
    realtime: bool,
) -> Result<Child, String> {
    if let Some(parent) = Path::new(output_path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|e| format!("mkdir {}: {e}", parent.display()))?;
        }
    }

    let size_arg = format!("{width}x{height}");
    let fps_arg = fps.max(1).to_string();

    let mut cmd = crate::ffmpeg::command();
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
            if realtime {
                // 実時間で書き出しが追いつかないと、録画の時間が抜け落ちる (1080p で 60fps でも 30fps でも落ちた)。
                // 実時間向けの速い設定にする
                let threads = std::thread::available_parallelism().map(|n| n.get().min(16)).unwrap_or(4).to_string();
                cmd.args(["-deadline", "realtime", "-cpu-used", "8", "-row-mt", "1", "-tile-columns", "2", "-lag-in-frames", "0", "-threads", &threads]);
            }
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
        .map_err(|e| crate::ffmpeg::spawn_error(&e))
}

/// 録画の後から重ねる音の区間。音声・動画ファイルの file_offset 秒から、録画の start〜end 秒に置く。
#[derive(Debug, Clone, PartialEq)]
pub struct AudioSegment {
    pub path: String,
    pub file_offset: f64,
    pub start: f64,
    pub end: f64,
}

/// 録画した映像 (音なし) に、音の区間を重ねて書き直す。映像はそのまま写す (-c:v copy)。
/// 区間は重ならない前提で、間は無音で埋める。失敗したときは元の映像を残す。
pub fn mux_audio_segments(video_path: &str, segments: &[AudioSegment], format: RecordFormat) -> Result<(), String> {
    let mut segs: Vec<&AudioSegment> = segments
        .iter()
        .filter(|s| !s.path.trim().is_empty() && s.end - s.start >= 0.02)
        .collect();
    if segs.is_empty() {
        return Ok(());
    }
    segs.sort_by(|a, b| a.start.total_cmp(&b.start));

    let p = Path::new(video_path);
    let ext = p.extension().and_then(|e| e.to_str()).unwrap_or("mp4");
    let tmp = p.with_extension(format!("audio_tmp.{ext}"));
    let tmp_s = tmp.to_string_lossy().to_string();

    let mut cmd = crate::ffmpeg::command();
    cmd.args(["-y", "-loglevel", "error", "-i", video_path]);
    let mut filter = String::new();
    let mut labels = String::new();
    let mut cursor = 0.0f64;
    for (i, s) in segs.iter().enumerate() {
        let start = s.start.max(cursor);
        let len = s.end - start;
        if len <= 0.0 {
            continue;
        }
        let gap_ms = ((start - cursor) * 1000.0).round().max(0.0) as i64;
        cmd.args([
            "-ss",
            &format!("{:.3}", s.file_offset.max(0.0)),
            "-t",
            &format!("{:.3}", len),
            "-i",
            &s.path,
        ]);
        let k = i + 1;
        filter.push_str(&format!(
            "[{k}:a:0]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,apad,atrim=end={len:.3},adelay={gap_ms}|{gap_ms},asetpts=N/SR/TB[a{i}];"
        ));
        labels.push_str(&format!("[a{i}]"));
        cursor = start + len;
    }
    let n = labels.matches("[a").count();
    if n == 0 {
        return Ok(());
    }
    filter.push_str(&format!("{labels}concat=n={n}:v=0:a=1[aout]"));
    cmd.args(["-filter_complex", &filter, "-map", "0:v", "-map", "[aout]", "-c:v", "copy"]);
    match format {
        RecordFormat::Mp4 => {
            cmd.args(["-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]);
        }
        RecordFormat::WebmAlpha => {
            cmd.args(["-c:a", "libopus", "-b:a", "160k"]);
        }
    }
    cmd.arg(&tmp_s);
    cmd.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::piped());
    #[cfg(target_os = "windows")]
    {
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    let out = cmd
        .output()
        .map_err(|e| format!("FFmpeg を起動できません: {e}"))?;
    if !out.status.success() {
        let _ = std::fs::remove_file(&tmp);
        let msg = String::from_utf8_lossy(&out.stderr);
        return Err(format!("音を入れられませんでした: {}", msg.trim()));
    }
    std::fs::remove_file(p).map_err(|e| format!("元の録画を置き換えられません: {e}"))?;
    std::fs::rename(&tmp, p).map_err(|e| format!("録画の名前を戻せません: {e}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;

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

    fn write_tone_wav(path: &std::path::Path, secs: f32) {
        let sr = 22050u32;
        let n = (secs * sr as f32) as u32;
        let mut b: Vec<u8> = Vec::new();
        b.extend_from_slice(b"RIFF");
        b.extend_from_slice(&(36 + n * 2).to_le_bytes());
        b.extend_from_slice(b"WAVEfmt ");
        b.extend_from_slice(&16u32.to_le_bytes());
        b.extend_from_slice(&1u16.to_le_bytes());
        b.extend_from_slice(&1u16.to_le_bytes());
        b.extend_from_slice(&sr.to_le_bytes());
        b.extend_from_slice(&(sr * 2).to_le_bytes());
        b.extend_from_slice(&2u16.to_le_bytes());
        b.extend_from_slice(&16u16.to_le_bytes());
        b.extend_from_slice(b"data");
        b.extend_from_slice(&(n * 2).to_le_bytes());
        for i in 0..n {
            let v = ((i as f32 * 440.0 * std::f32::consts::TAU / sr as f32).sin() * 12000.0) as i16;
            b.extend_from_slice(&v.to_le_bytes());
        }
        std::fs::write(path, b).unwrap();
    }

    fn probe(path: &std::path::Path, args: &[&str]) -> String {
        let out = Command::new("ffprobe")
            .args(["-v", "error"])
            .args(args)
            .arg(path)
            .output()
            .expect("ffprobe");
        String::from_utf8_lossy(&out.stdout).trim().to_string()
    }

    fn max_volume(path: &std::path::Path, from: f64, len: f64) -> f64 {
        let out = Command::new("ffmpeg")
            .args(["-hide_banner", "-ss", &format!("{from}"), "-t", &format!("{len}"), "-i"])
            .arg(path)
            .args(["-map", "0:a", "-af", "volumedetect", "-f", "null", "-"])
            .output()
            .expect("ffmpeg");
        let err = String::from_utf8_lossy(&out.stderr);
        err.lines()
            .find_map(|l| l.split("max_volume:").nth(1))
            .and_then(|v| v.trim().trim_end_matches("dB").trim().parse().ok())
            .unwrap_or(-91.0)
    }

    #[test]
    fn muxes_audio_segments_into_recording() {
        let dir = std::env::temp_dir().join("vrmviewer_rec_mux_test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let wav = dir.join("tone.wav");
        write_tone_wav(&wav, 3.0);
        let w = 64u32;
        let h = 64u32;
        let mut frame = vec![0u8; (w * h * 4) as usize];
        for (i, px) in frame.chunks_mut(4).enumerate() {
            px[0] = 200;
            px[3] = if i % 64 < 32 { 255 } else { 0 };
        }
        let segs = vec![
            AudioSegment { path: wav.to_string_lossy().into(), file_offset: 0.2, start: 0.5, end: 1.0 },
            AudioSegment { path: wav.to_string_lossy().into(), file_offset: 0.0, start: 1.2, end: 2.0 },
        ];
        for (name, fmt) in [("a.mp4", RecordFormat::Mp4), ("a.webm", RecordFormat::WebmAlpha)] {
            let out = dir.join(name);
            let mut rec = FfmpegRecorder::start_sync(out.to_str().unwrap(), w, h, 30, fmt, None).unwrap();
            for _ in 0..60 {
                rec.write_frame_blocking(&frame).unwrap();
            }
            rec.finish().unwrap();
            mux_audio_segments(out.to_str().unwrap(), &segs, fmt).expect("mux");
            let streams = probe(&out, &["-show_entries", "stream=codec_type", "-of", "csv=p=0"]);
            assert!(streams.contains("video") && streams.contains("audio"), "{name}: {streams}");
            let adur: f64 = probe(&out, &["-select_streams", "a:0", "-show_entries", "format=duration", "-of", "csv=p=0"])
                .parse()
                .unwrap_or(0.0);
            assert!((adur - 2.0).abs() < 0.15, "{name}: duration {adur}");
            if fmt == RecordFormat::WebmAlpha {
                let tags = probe(&out, &["-select_streams", "v:0", "-show_entries", "stream_tags", "-of", "default"]);
                assert!(tags.to_lowercase().contains("alpha_mode=1"), "alpha が残っていない: {tags}");
            }
            // 区間の前 (0〜0.4 秒) と間 (1.05〜1.15 秒) は無音、区間の中 (0.6〜0.9 秒) は鳴る
            assert!(max_volume(&out, 0.0, 0.4) < -60.0, "{name}: 区間の前が無音でない");
            assert!(max_volume(&out, 1.05, 0.1) < -60.0, "{name}: 区間の間が無音でない");
            assert!(max_volume(&out, 0.6, 0.3) > -20.0, "{name}: 区間で鳴っていない");
            assert!(!dir.join(format!("a.audio_tmp.{}", if fmt == RecordFormat::Mp4 { "mp4" } else { "webm" })).exists());
        }
        let _ = std::fs::remove_dir_all(&dir);
    }
}
