use super::spout_win::SpoutSender;
use super::vcam_win::{probe_vcam_status, WindowsVcamSender};
use super::PlatformState;
use std::collections::BTreeMap;
use std::ffi::c_void;
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use windows::Win32::Foundation::HWND;
use windows::Win32::System::Threading::GetCurrentThreadId;
use windows::Win32::UI::Input::KeyboardAndMouse::{
    RegisterHotKey, UnregisterHotKey, HOT_KEY_MODIFIERS, MOD_ALT, MOD_CONTROL, MOD_NOREPEAT,
    MOD_SHIFT,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetMessageW, GetWindowLongPtrW, PostThreadMessageW, SetWindowLongPtrW, SetWindowPos,
    GWL_EXSTYLE, MSG, SWP_FRAMECHANGED, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SWP_NOZORDER,
    WM_HOTKEY, WM_QUIT, WS_EX_LAYERED, WS_EX_TRANSPARENT,
};

pub struct HotkeyThreadHandle {
    pub thread_id: u32,
    pub join: Option<JoinHandle<()>>,
}

pub fn set_window_click_through(native_hwnd: i64, enabled: bool) -> bool {
    if native_hwnd == 0 {
        return false;
    }
    let hwnd = HWND(native_hwnd as usize as *mut c_void);
    unsafe {
        let style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        let layered = WS_EX_LAYERED.0 as isize;
        let transparent = WS_EX_TRANSPARENT.0 as isize;
        let new_style = if enabled {
            style | layered | transparent
        } else {
            style & !(layered | transparent)
        };
        let _ = SetWindowLongPtrW(hwnd, GWL_EXSTYLE, new_style);
        let _ = SetWindowPos(
            hwnd,
            None,
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
        );
        true
    }
}

pub fn refresh_window_frame(native_hwnd: i64) -> bool {
    if native_hwnd == 0 {
        return false;
    }
    let hwnd = HWND(native_hwnd as usize as *mut c_void);
    unsafe {
        SetWindowPos(
            hwnd,
            None,
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
        )
        .is_ok()
    }
}

pub fn configure_global_hotkeys(
    state: &Arc<Mutex<PlatformState>>,
    enabled: bool,
    bindings_json: &str,
) -> bool {
    stop_hotkey_thread(state);
    if !enabled {
        return true;
    }
    let bindings: BTreeMap<String, String> =
        serde_json::from_str(bindings_json).unwrap_or_default();
    if bindings.is_empty() {
        return true;
    }

    let state_clone = Arc::clone(state);
    let (tid_tx, tid_rx) = std::sync::mpsc::channel::<u32>();

    let join = std::thread::Builder::new()
        .name("vrm-global-hotkeys".into())
        .spawn(move || unsafe {
            let tid = GetCurrentThreadId();
            let _ = tid_tx.send(tid);

            let mut id_to_action: BTreeMap<i32, String> = BTreeMap::new();
            let mut next_id: i32 = 1;
            for (combo, action) in bindings {
                if let Some((mods, vk)) = parse_hotkey_combo(&combo) {
                    if RegisterHotKey(None, next_id, mods | MOD_NOREPEAT, vk).is_ok() {
                        id_to_action.insert(next_id, action);
                    }
                    next_id += 1;
                }
            }

            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).as_bool() {
                if msg.message == WM_HOTKEY {
                    let hk_id = msg.wParam.0 as i32;
                    if let Some(action) = id_to_action.get(&hk_id) {
                        if let Ok(mut guard) = state_clone.lock() {
                            guard.pending_hotkeys.push(action.clone());
                        }
                    }
                }
            }

            for hk_id in id_to_action.keys() {
                let _ = UnregisterHotKey(None, *hk_id);
            }
        });

    match join {
        Ok(jh) => {
            if let Ok(tid) = tid_rx.recv() {
                if let Ok(mut guard) = state.lock() {
                    guard.hotkey_thread = Some(HotkeyThreadHandle {
                        thread_id: tid,
                        join: Some(jh),
                    });
                }
                return true;
            }
            false
        }
        Err(_) => false,
    }
}

fn stop_hotkey_thread(state: &Arc<Mutex<PlatformState>>) {
    let handle = {
        let mut guard = match state.lock() {
            Ok(g) => g,
            Err(_) => return,
        };
        guard.hotkey_thread.take()
    };
    if let Some(mut h) = handle {
        unsafe {
            let _ = PostThreadMessageW(h.thread_id, WM_QUIT, Default::default(), Default::default());
        }
        if let Some(j) = h.join.take() {
            let _ = j.join();
        }
    }
}

fn parse_hotkey_combo(combo: &str) -> Option<(HOT_KEY_MODIFIERS, u32)> {
    let mut mods = HOT_KEY_MODIFIERS(0);
    let mut key_part: Option<&str> = None;
    for tok in combo.split('+') {
        let t = tok.trim();
        if t.eq_ignore_ascii_case("ctrl") || t.eq_ignore_ascii_case("control") {
            mods |= MOD_CONTROL;
        } else if t.eq_ignore_ascii_case("shift") {
            mods |= MOD_SHIFT;
        } else if t.eq_ignore_ascii_case("alt") {
            mods |= MOD_ALT;
        } else {
            key_part = Some(t);
        }
    }
    let k = key_part?;
    let vk = match k.to_ascii_uppercase().as_str() {
        "F1" => 0x70,
        "F2" => 0x71,
        "F3" => 0x72,
        "F4" => 0x73,
        "F5" => 0x74,
        "F6" => 0x75,
        "F7" => 0x76,
        "F8" => 0x77,
        "F9" => 0x78,
        "F10" => 0x79,
        "F11" => 0x7A,
        "F12" => 0x7B,
        s if s.len() == 1 => {
            let b = s.as_bytes()[0];
            if b.is_ascii_alphanumeric() {
                b as u32
            } else {
                return None;
            }
        }
        _ => return None,
    };
    Some((mods, vk))
}

pub fn set_spout_enabled(
    state: &Arc<Mutex<PlatformState>>,
    enabled: bool,
    sender_name: &str,
) -> Result<String, String> {
    let mut guard = state.lock().map_err(|_| "lock poisoned".to_string())?;
    if !enabled {
        guard.spout = None;
        return Ok("Spout2 stopped".into());
    }
    let name = if sender_name.trim().is_empty() {
        "UtsushiMirror"
    } else {
        sender_name.trim()
    };
    if let Some(existing) = &guard.spout {
        if existing.sender_name() == name {
            return Ok(format!("Spout2 active ({name})"));
        }
    }
    guard.spout = None;
    let sender = SpoutSender::new(name)?;
    guard.spout = Some(sender);
    Ok(format!("Spout2 started ({name})"))
}

pub fn send_spout_frame(
    state: &Arc<Mutex<PlatformState>>,
    width: u32,
    height: u32,
    rgba: &[u8],
) -> bool {
    let Ok(mut guard) = state.lock() else {
        return false;
    };
    let Some(sender) = &mut guard.spout else {
        return false;
    };
    sender.send_rgba(width, height, rgba).is_ok()
}

pub fn set_vcam_enabled(
    state: &Arc<Mutex<PlatformState>>,
    enabled: bool,
    width: u32,
    height: u32,
) -> (bool, String) {
    let Ok(mut guard) = state.lock() else {
        return (false, "lock poisoned".into());
    };
    if !enabled {
        guard.vcam = None;
        return (true, "Virtual camera stopped".into());
    }
    match WindowsVcamSender::open(width, height) {
        Ok(sender) => {
            guard.vcam = Some(sender);
            (true, "Virtual camera active".into())
        }
        Err(msg) => {
            guard.vcam = None;
            (false, msg)
        }
    }
}

pub fn send_vcam_frame(
    state: &Arc<Mutex<PlatformState>>,
    width: u32,
    height: u32,
    rgba: &[u8],
) -> bool {
    let Ok(mut guard) = state.lock() else {
        return false;
    };
    let Some(vcam) = &mut guard.vcam else {
        return false;
    };
    vcam.send_rgba(width, height, rgba).is_ok()
}

pub fn get_vcam_status_json(state: &Arc<Mutex<PlatformState>>) -> String {
    let active = state.lock().is_ok_and(|g| g.vcam.is_some());
    let status = probe_vcam_status(active);
    serde_json::to_string(&status).unwrap_or_default()
}

pub fn cleanup(state: &Arc<Mutex<PlatformState>>) {
    stop_hotkey_thread(state);
    if let Ok(mut guard) = state.lock() {
        guard.spout = None;
        guard.vcam = None;
    }
}
