use std::sync::{Arc, Mutex};

#[cfg(target_os = "windows")]
mod spout_win;
#[cfg(target_os = "windows")]
mod vcam_win;
#[cfg(target_os = "windows")]
mod windows;
#[cfg(target_os = "windows")]
use windows as imp;

#[cfg(not(target_os = "windows"))]
mod linux;
#[cfg(not(target_os = "windows"))]
mod vcam_linux;
#[cfg(not(target_os = "windows"))]
use linux as imp;

#[derive(Default)]
pub struct PlatformState {
    pub pending_hotkeys: Vec<String>,
    #[cfg(target_os = "windows")]
    pub hotkey_thread: Option<windows::HotkeyThreadHandle>,
    #[cfg(target_os = "windows")]
    pub spout: Option<spout_win::SpoutSender>,
    #[cfg(target_os = "windows")]
    pub vcam: Option<vcam_win::WindowsVcamSender>,
}

pub fn set_window_click_through(native_hwnd: i64, enabled: bool) -> bool {
    imp::set_window_click_through(native_hwnd, enabled)
}

pub fn refresh_window_frame(native_hwnd: i64) -> bool {
    imp::refresh_window_frame(native_hwnd)
}

pub fn configure_global_hotkeys(
    state: &Arc<Mutex<PlatformState>>,
    enabled: bool,
    bindings_json: &str,
) -> bool {
    imp::configure_global_hotkeys(state, enabled, bindings_json)
}

pub fn poll_global_hotkeys(state: &Arc<Mutex<PlatformState>>) -> Vec<String> {
    if let Ok(mut guard) = state.lock() {
        std::mem::take(&mut guard.pending_hotkeys)
    } else {
        Vec::new()
    }
}

pub fn set_spout_enabled(
    state: &Arc<Mutex<PlatformState>>,
    enabled: bool,
    sender_name: &str,
) -> Result<String, String> {
    imp::set_spout_enabled(state, enabled, sender_name)
}

pub fn send_spout_frame(
    state: &Arc<Mutex<PlatformState>>,
    width: u32,
    height: u32,
    rgba: &[u8],
) -> bool {
    imp::send_spout_frame(state, width, height, rgba)
}

pub fn set_vcam_enabled(
    state: &Arc<Mutex<PlatformState>>,
    enabled: bool,
    width: u32,
    height: u32,
) -> (bool, String) {
    imp::set_vcam_enabled(state, enabled, width, height)
}

pub fn send_vcam_frame(
    state: &Arc<Mutex<PlatformState>>,
    width: u32,
    height: u32,
    rgba: &[u8],
) -> bool {
    imp::send_vcam_frame(state, width, height, rgba)
}

pub fn get_vcam_status_json(state: &Arc<Mutex<PlatformState>>) -> String {
    imp::get_vcam_status_json(state)
}

pub fn cleanup(state: &Arc<Mutex<PlatformState>>) {
    imp::cleanup(state);
}
