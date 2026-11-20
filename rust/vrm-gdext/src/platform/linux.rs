use super::vcam_linux::probe_vcam_status;
use super::PlatformState;
use std::sync::{Arc, Mutex};

pub fn set_window_click_through(_native_hwnd: i64, _enabled: bool) -> bool {
    false
}

pub fn refresh_window_frame(_native_hwnd: i64) -> bool {
    false
}

pub fn configure_global_hotkeys(
    _state: &Arc<Mutex<PlatformState>>,
    _enabled: bool,
    _bindings_json: &str,
) -> bool {
    false
}

pub fn set_spout_enabled(
    _state: &Arc<Mutex<PlatformState>>,
    enabled: bool,
    _sender_name: &str,
) -> Result<String, String> {
    if !enabled {
        Ok("Spout2 disabled".into())
    } else {
        Err("Spout2 is Windows-only (use Virtual Camera / v4l2loopback or NDI/OBS on Linux)".into())
    }
}

pub fn send_spout_frame(
    _state: &Arc<Mutex<PlatformState>>,
    _width: u32,
    _height: u32,
    _rgba: &[u8],
) -> bool {
    false
}

pub fn set_vcam_enabled(
    _state: &Arc<Mutex<PlatformState>>,
    enabled: bool,
    _width: u32,
    _height: u32,
) -> (bool, String) {
    if !enabled {
        return (true, "Virtual camera disabled".into());
    }
    let st = probe_vcam_status(false);
    (false, st.message)
}

pub fn send_vcam_frame(
    _state: &Arc<Mutex<PlatformState>>,
    _width: u32,
    _height: u32,
    _rgba: &[u8],
) -> bool {
    false
}

pub fn get_vcam_status_json(_state: &Arc<Mutex<PlatformState>>) -> String {
    let status = probe_vcam_status(false);
    serde_json::to_string(&status).unwrap_or_default()
}

pub fn cleanup(_state: &Arc<Mutex<PlatformState>>) {}
