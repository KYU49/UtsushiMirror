pub mod lipsync;
pub mod osc_receiver;
pub mod platform;
pub mod recorder;
pub mod ws_server;

use godot::prelude::*;
use osc_receiver::OscReceiverHandle;
use recorder::{FfmpegRecorder, RecordFormat};
use std::sync::{Arc, Mutex};
use vrm_protocol::{QueuedRpcRequest, RpcResponse};
use ws_server::WsServerHandle;

struct VrmGdextExtension;

#[gdextension]
unsafe impl ExtensionLibrary for VrmGdextExtension {}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct VrmBridge {
    base: Base<Node>,
    ws_server: Option<WsServerHandle>,
    osc_receiver: Option<OscReceiverHandle>,
    rpc_rx: Option<crossbeam_channel::Receiver<QueuedRpcRequest>>,
    last_vmc_seq: u64,
    platform_state: Arc<Mutex<platform::PlatformState>>,
    recorder: Option<FfmpegRecorder>,
}

#[godot_api]
impl INode for VrmBridge {
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            ws_server: None,
            osc_receiver: None,
            rpc_rx: None,
            last_vmc_seq: 0,
            platform_state: Arc::new(Mutex::new(platform::PlatformState::default())),
            recorder: None,
        }
    }

    fn exit_tree(&mut self) {
        if let Some(rec) = self.recorder.take() {
            let _ = rec.finish();
        }
        self.stop_servers();
        platform::cleanup(&self.platform_state);
    }
}

#[godot_api]
impl VrmBridge {
    #[func]
    pub fn start_servers(&mut self, ws_port: i32, osc_port: i32) -> bool {
        self.stop_servers();
        let ws_p = u16::try_from(ws_port).unwrap_or(19100);
        let osc_p = u16::try_from(osc_port).unwrap_or(39539);
        let (tx, rx) = crossbeam_channel::unbounded();
        match WsServerHandle::start(ws_p, tx) {
            Ok(ws) => self.ws_server = Some(ws),
            Err(e) => {
                godot_error!("VrmBridge failed to start WebSocket server on port {ws_p}: {e}");
                return false;
            }
        }
        match OscReceiverHandle::start(osc_p) {
            Ok(osc) => self.osc_receiver = Some(osc),
            Err(e) => {
                godot_error!("VrmBridge failed to start OSC receiver on port {osc_p}: {e}");
            }
        }
        self.rpc_rx = Some(rx);
        godot_print!("VrmBridge servers started (WS:{ws_p}, OSC:{osc_p})");
        true
    }

    #[func]
    pub fn stop_servers(&mut self) {
        if let Some(ws) = self.ws_server.take() {
            ws.stop();
        }
        if let Some(osc) = self.osc_receiver.take() {
            osc.stop();
        }
        self.rpc_rx = None;
    }

    #[func]
    pub fn is_servers_running(&self) -> bool {
        self.ws_server.is_some()
    }

    #[func]
    pub fn poll_rpc_requests(&self) -> PackedStringArray {
        let mut out = PackedStringArray::new();
        if let Some(rx) = &self.rpc_rx {
            while let Ok(req) = rx.try_recv() {
                if let Ok(line) = serde_json::to_string(&req) {
                    out.push(&line);
                }
            }
        }
        out
    }

    #[func]
    pub fn send_rpc_response(&self, client_id: i64, response_json: GString) {
        if let Some(ws) = &self.ws_server {
            ws.send_to_client(client_id as u64, response_json.to_string());
        }
    }

    #[func]
    pub fn build_rpc_ok(&self, id_json: GString, result_json: GString) -> GString {
        let id = serde_json::from_str(&id_json.to_string()).unwrap_or(serde_json::Value::Null);
        let result =
            serde_json::from_str(&result_json.to_string()).unwrap_or(serde_json::Value::Null);
        let resp = RpcResponse::ok(id, result);
        GString::from(&serde_json::to_string(&resp).unwrap_or_default())
    }

    #[func]
    pub fn build_rpc_err(&self, id_json: GString, code: i32, message: GString) -> GString {
        let id = serde_json::from_str(&id_json.to_string()).unwrap_or(serde_json::Value::Null);
        let resp = RpcResponse::err(
            id,
            vrm_protocol::RpcError {
                code,
                message: message.to_string(),
                data: None,
            },
        );
        GString::from(&serde_json::to_string(&resp).unwrap_or_default())
    }

    #[func]
    pub fn poll_vmc_frame(&mut self) -> GString {
        if let Some(osc) = &self.osc_receiver {
            if let Some((seq, json)) = osc.take_if_newer(self.last_vmc_seq) {
                self.last_vmc_seq = seq;
                return GString::from(&json);
            }
        }
        GString::new()
    }

    #[func]
    pub fn set_window_click_through(&self, native_hwnd: i64, enabled: bool) -> bool {
        platform::set_window_click_through(native_hwnd, enabled)
    }

    #[func]
    pub fn refresh_window_frame(&self, native_hwnd: i64) -> bool {
        platform::refresh_window_frame(native_hwnd)
    }

    #[func]
    pub fn configure_global_hotkeys(&self, enabled: bool, bindings_json: GString) -> bool {
        platform::configure_global_hotkeys(&self.platform_state, enabled, &bindings_json.to_string())
    }

    #[func]
    pub fn poll_global_hotkeys(&self) -> PackedStringArray {
        let mut out = PackedStringArray::new();
        for action in platform::poll_global_hotkeys(&self.platform_state) {
            out.push(&action);
        }
        out
    }

    #[func]
    pub fn start_recording(
        &mut self,
        output_path: GString,
        width: i32,
        height: i32,
        fps: i32,
        format: GString,
        audio_path: GString,
        sync_mode: bool,
    ) -> VarDictionary {
        let mut dict = VarDictionary::new();
        if self.recorder.is_some() {
            dict.set("ok", false);
            dict.set("error", "Recording already active");
            return dict;
        }
        let w = u32::try_from(width).unwrap_or(1280).max(2);
        let h = u32::try_from(height).unwrap_or(720).max(2);
        let f = u32::try_from(fps).unwrap_or(60).max(1);
        let fmt = RecordFormat::from_str(&format.to_string());
        let aud_s = audio_path.to_string();
        let aud_opt = if aud_s.trim().is_empty() {
            None
        } else {
            Some(aud_s.as_str())
        };
        let res = if sync_mode {
            FfmpegRecorder::start_sync(&output_path.to_string(), w, h, f, fmt, aud_opt)
        } else {
            FfmpegRecorder::start_async(&output_path.to_string(), w, h, f, fmt, aud_opt)
        };
        match res {
            Ok(rec) => {
                dict.set("ok", true);
                dict.set("output_path", &GString::from(rec.output_path()));
                self.recorder = Some(rec);
            }
            Err(e) => {
                dict.set("ok", false);
                dict.set("error", &GString::from(&e));
            }
        }
        dict
    }

    #[func]
    pub fn push_recording_frame(&mut self, rgba: PackedByteArray, sync_mode: bool) -> bool {
        let Some(rec) = &mut self.recorder else {
            return false;
        };
        if sync_mode {
            rec.write_frame_blocking(rgba.as_slice()).is_ok()
        } else {
            rec.push_frame_async(rgba.as_slice())
        }
    }

    #[func]
    pub fn stop_recording(&mut self) -> VarDictionary {
        let mut dict = VarDictionary::new();
        let Some(rec) = self.recorder.take() else {
            dict.set("ok", false);
            dict.set("error", "Not currently recording");
            return dict;
        };
        match rec.finish() {
            Ok((path, frames)) => {
                dict.set("ok", true);
                dict.set("output_path", &GString::from(&path));
                dict.set("frames", frames as i64);
            }
            Err(e) => {
                dict.set("ok", false);
                dict.set("error", &GString::from(&e));
            }
        }
        dict
    }

    #[func]
    pub fn is_recording(&self) -> bool {
        self.recorder.is_some()
    }

    #[func]
    pub fn set_spout_enabled(&self, enabled: bool, sender_name: GString) -> VarDictionary {
        let mut dict = VarDictionary::new();
        match platform::set_spout_enabled(&self.platform_state, enabled, &sender_name.to_string()) {
            Ok(msg) => {
                dict.set("ok", true);
                dict.set("enabled", enabled);
                dict.set("message", &GString::from(&msg));
            }
            Err(e) => {
                dict.set("ok", false);
                dict.set("enabled", false);
                dict.set("error", &GString::from(&e));
            }
        }
        dict
    }

    #[func]
    pub fn send_spout_frame(&self, width: i32, height: i32, rgba: PackedByteArray) -> bool {
        let w = u32::try_from(width).unwrap_or(0);
        let h = u32::try_from(height).unwrap_or(0);
        platform::send_spout_frame(&self.platform_state, w, h, rgba.as_slice())
    }

    #[func]
    pub fn set_vcam_enabled(&self, enabled: bool, width: i32, height: i32) -> VarDictionary {
        let mut dict = VarDictionary::new();
        let w = u32::try_from(width).unwrap_or(1280);
        let h = u32::try_from(height).unwrap_or(720);
        let (ok, msg) = platform::set_vcam_enabled(&self.platform_state, enabled, w, h);
        dict.set("ok", ok);
        dict.set("active", ok && enabled);
        dict.set("message", &GString::from(&msg));
        dict
    }

    #[func]
    pub fn send_vcam_frame(&self, width: i32, height: i32, rgba: PackedByteArray) -> bool {
        let w = u32::try_from(width).unwrap_or(0);
        let h = u32::try_from(height).unwrap_or(0);
        platform::send_vcam_frame(&self.platform_state, w, h, rgba.as_slice())
    }

    #[func]
    pub fn get_vcam_status_json(&self) -> GString {
        GString::from(&platform::get_vcam_status_json(&self.platform_state))
    }

    #[func]
    pub fn read_glb_chunks(&self, path: GString) -> VarDictionary {
        let mut dict = VarDictionary::new();
        match std::fs::read(path.to_string()) {
            Ok(bytes) => match parse_glb_raw(&bytes) {
                Ok((json_str, bin_bytes)) => {
                    dict.set("ok", true);
                    dict.set("json", &GString::from(&json_str));
                    dict.set("bin", &PackedByteArray::from(bin_bytes.as_slice()));
                }
                Err(e) => {
                    dict.set("ok", false);
                    dict.set("error", &GString::from(&e));
                }
            },
            Err(e) => {
                dict.set("ok", false);
                dict.set("error", &GString::from(&format!("Failed to read file: {e}")));
            }
        }
        dict
    }

    #[func]
    pub fn encode_png_base64(&self, png_bytes: PackedByteArray) -> GString {
        use base64::Engine;
        let b64 = base64::engine::general_purpose::STANDARD.encode(png_bytes.as_slice());
        GString::from(&b64)
    }

    /// 音声・動画ファイルから、口の動きと感情の表を作る (lipsync.rs)。
    /// 戻り値: {ok, fps, stride, duration, frames: PackedFloat32Array} / {ok: false, error}
    #[func]
    pub fn analyze_lipsync(&self, path: GString) -> VarDictionary {
        let mut dict = VarDictionary::new();
        match lipsync::analyze_file(&path.to_string()) {
            Ok(a) => {
                dict.set("ok", true);
                dict.set("fps", lipsync::FPS);
                dict.set("stride", lipsync::STRIDE as i64);
                dict.set("duration", a.duration);
                dict.set("frames", &PackedFloat32Array::from(a.frames.as_slice()));
            }
            Err(e) => {
                dict.set("ok", false);
                dict.set("error", &GString::from(&e));
            }
        }
        dict
    }
}

fn parse_glb_raw(bytes: &[u8]) -> Result<(String, Vec<u8>), String> {
    if bytes.len() < 12 {
        return Err("File too small to be GLB".into());
    }
    let magic = u32::from_le_bytes(bytes[0..4].try_into().unwrap());
    let version = u32::from_le_bytes(bytes[4..8].try_into().unwrap());
    let total_len = u32::from_le_bytes(bytes[8..12].try_into().unwrap()) as usize;
    if magic != 0x4654_6C67 {
        return Err("Invalid GLB magic header".into());
    }
    if version != 2 {
        return Err(format!("Unsupported GLB version: {version}"));
    }
    let end = total_len.min(bytes.len());
    let mut offset = 12usize;
    let mut json_str = None;
    let mut bin_chunk = Vec::new();
    while offset + 8 <= end {
        let chunk_len = u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap()) as usize;
        let chunk_type = u32::from_le_bytes(bytes[offset + 4..offset + 8].try_into().unwrap());
        offset += 8;
        if offset + chunk_len > end {
            return Err("GLB chunk exceeds file length".into());
        }
        let data = &bytes[offset..offset + chunk_len];
        match chunk_type {
            0x4E4F_534A => {
                json_str = Some(
                    String::from_utf8(data.to_vec())
                        .map_err(|e| format!("Invalid UTF-8 in GLB JSON chunk: {e}"))?,
                );
            }
            0x004E_4942 => {
                bin_chunk = data.to_vec();
            }
            _ => {}
        }
        offset += chunk_len;
    }
    let json = json_str.ok_or_else(|| "Missing JSON chunk in GLB".to_string())?;
    Ok((json, bin_chunk))
}
