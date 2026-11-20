use std::ptr;
use windows::core::PCWSTR;
use windows::Win32::Foundation::{CloseHandle, HANDLE};
use windows::Win32::Security::{
    AllocateAndInitializeSid, CheckTokenMembership, FreeSid, PSID, SECURITY_NT_AUTHORITY,
};
use windows::Win32::System::Memory::{
    CreateFileMappingW, MapViewOfFile, UnmapViewOfFile, FILE_MAP_ALL_ACCESS,
    MEMORY_MAPPED_VIEW_ADDRESS, PAGE_READWRITE,
};

/// Virtual Camera support on Windows with graceful admin-privilege handling:
/// - Detects registered virtual camera providers in HKLM (OBS VirtualCam DirectShow/MF CLSID
///   registered via scripts/register_vcam.ps1 or OBS Studio installer).
/// - Never crashes or demands elevation during normal startup; if unregistered,
///   disables ONLY the Virtual Camera feature cleanly and reports status + instructions.

const OBS_VCAM_CLSID_SUBKEY: &str =
    r"SOFTWARE\Classes\CLSID\{A3FCE0F5-3493-419F-958A-ABA1250EC20B}";
const OBS_VCAM_SHM_NAME: &str = "OBSVirtualCamVideo";
const ALIGN_SIZE: usize = 32;
const FRAME_HEADER_SIZE: usize = 32;

#[repr(C)]
struct QueueHeader {
    write_idx: u32,
    read_idx: u32,
    state: u32, // 0 = invalid, 1 = starting, 2 = ready, 3 = stopping
    offsets: [u32; 3],
    type_id: u32,
    cx: u32,
    cy: u32,
    interval: u64,
    reserved: [u32; 8],
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct VcamStatus {
    pub available: bool,
    pub active: bool,
    pub backend: String,
    pub requires_admin_registration: bool,
    pub is_admin: bool,
    pub message: String,
}

pub struct WindowsVcamSender {
    handle: HANDLE,
    view: MEMORY_MAPPED_VIEW_ADDRESS,
    mapped_size: usize,
    width: u32,
    height: u32,
    frame_counter: u64,
    nv12_scratch: Vec<u8>,
}

unsafe impl Send for WindowsVcamSender {}

impl WindowsVcamSender {
    pub fn open(width: u32, height: u32) -> Result<Self, String> {
        let status = probe_vcam_status(false);
        if !status.available {
            return Err(status.message);
        }
        let mut s = Self {
            handle: HANDLE::default(),
            view: MEMORY_MAPPED_VIEW_ADDRESS::default(),
            mapped_size: 0,
            width: 0,
            height: 0,
            frame_counter: 0,
            nv12_scratch: Vec::new(),
        };
        s.resize_queue(width, height)?;
        Ok(s)
    }

    pub fn send_rgba(&mut self, width: u32, height: u32, rgba: &[u8]) -> Result<(), String> {
        if width == 0 || height == 0 || rgba.len() != (width as usize * height as usize * 4) {
            return Err("Invalid RGBA buffer".into());
        }
        if self.width != width || self.height != height || self.view.Value.is_null() {
            self.resize_queue(width, height)?;
        }
        rgba_to_nv12(width, height, rgba, &mut self.nv12_scratch);
        let y_bytes = (width as usize) * (height as usize);
        let uv_bytes = y_bytes / 2;
        let frame_bytes = y_bytes + uv_bytes;

        unsafe {
            let hdr = &mut *(self.view.Value as *mut QueueHeader);
            let next_idx = hdr.write_idx.wrapping_add(1) % 3;
            let slot_off = hdr.offsets[next_idx as usize] as usize;
            let base_ptr = (self.view.Value as *mut u8).add(slot_off);
            // Frame timestamp header (u64 timestamp + u64 linesize info)
            let ts = self.frame_counter * hdr.interval;
            ptr::write_unaligned(base_ptr as *mut u64, ts);
            ptr::copy_nonoverlapping(
                self.nv12_scratch.as_ptr(),
                base_ptr.add(FRAME_HEADER_SIZE),
                frame_bytes,
            );
            hdr.write_idx = next_idx;
            hdr.read_idx = next_idx;
            hdr.state = 2;
        }
        self.frame_counter += 1;
        Ok(())
    }

    fn resize_queue(&mut self, width: u32, height: u32) -> Result<(), String> {
        self.close_mapping();
        // Ensure even dimensions for NV12
        let w = (width & !1).max(2);
        let h = (height & !1).max(2);
        let frame_size = (w as usize) * (h as usize) * 3 / 2;
        let hdr_size = align_up(std::mem::size_of::<QueueHeader>(), ALIGN_SIZE);
        let slot_stride = align_up(FRAME_HEADER_SIZE + frame_size, ALIGN_SIZE);
        let total = hdr_size + slot_stride * 3;

        let wname: Vec<u16> = OBS_VCAM_SHM_NAME
            .encode_utf16()
            .chain(std::iter::once(0))
            .collect();
        unsafe {
            let handle = CreateFileMappingW(
                HANDLE::default(),
                None,
                PAGE_READWRITE,
                0,
                total as u32,
                PCWSTR(wname.as_ptr()),
            )
            .map_err(|e| format!("CreateFileMappingW({OBS_VCAM_SHM_NAME}) failed: {e}"))?;
            let view = MapViewOfFile(handle, FILE_MAP_ALL_ACCESS, 0, 0, total);
            if view.Value.is_null() {
                let _ = CloseHandle(handle);
                return Err("MapViewOfFile for OBSVirtualCamVideo returned null".into());
            }
            ptr::write_bytes(view.Value as *mut u8, 0, total);
            let hdr = &mut *(view.Value as *mut QueueHeader);
            hdr.write_idx = 0;
            hdr.read_idx = 0;
            hdr.state = 1;
            hdr.offsets = [
                hdr_size as u32,
                (hdr_size + slot_stride) as u32,
                (hdr_size + slot_stride * 2) as u32,
            ];
            hdr.type_id = 0; // video_queue
            hdr.cx = w;
            hdr.cy = h;
            hdr.interval = 333_333; // ~30fps in 100ns units

            self.handle = handle;
            self.view = view;
            self.mapped_size = total;
            self.width = width;
            self.height = height;
        }
        Ok(())
    }

    fn close_mapping(&mut self) {
        unsafe {
            if !self.view.Value.is_null() {
                let hdr = &mut *(self.view.Value as *mut QueueHeader);
                hdr.state = 3;
                let _ = UnmapViewOfFile(self.view);
                self.view = MEMORY_MAPPED_VIEW_ADDRESS::default();
            }
            if !self.handle.is_invalid() {
                let _ = CloseHandle(self.handle);
                self.handle = HANDLE::default();
            }
        }
    }
}

impl Drop for WindowsVcamSender {
    fn drop(&mut self) {
        self.close_mapping();
    }
}

pub fn probe_vcam_status(active: bool) -> VcamStatus {
    let is_admin = is_process_elevated();
    let obs_registered = reg_clsid_exists(OBS_VCAM_CLSID_SUBKEY);

    if obs_registered {
        VcamStatus {
            available: true,
            active,
            backend: "obs_virtualcam_shm".into(),
            requires_admin_registration: false,
            is_admin,
            message: "仮想カメラ利用可能 (OBS Virtual Camera ドライバ登録済み)".into(),
        }
    } else {
        VcamStatus {
            available: false,
            active: false,
            backend: "none".into(),
            requires_admin_registration: true,
            is_admin,
            message: if is_admin {
                "仮想カメラドライバが未登録です。scripts/register_vcam.ps1 を実行して登録してください。"
                    .into()
            } else {
                "仮想カメラは現在無効です（未登録・管理者権限なし）。有効化するには管理者権限で scripts/register_vcam.ps1 を実行してください。"
                    .into()
            },
        }
    }
}

pub fn is_process_elevated() -> bool {
    unsafe {
        let mut admins_group: PSID = PSID::default();
        let ok = AllocateAndInitializeSid(
            &SECURITY_NT_AUTHORITY,
            2,
            0x0000_0020, // SECURITY_BUILTIN_DOMAIN_RID
            0x0000_0220, // DOMAIN_ALIAS_RID_ADMINS
            0,
            0,
            0,
            0,
            0,
            0,
            &mut admins_group,
        );
        if ok.is_err() {
            return false;
        }
        let mut is_member = windows::core::BOOL(0);
        let check = CheckTokenMembership(None, admins_group, &mut is_member);
        let _ = FreeSid(admins_group);
        check.is_ok() && is_member.as_bool()
    }
}

fn reg_clsid_exists(subkey: &str) -> bool {
    // Use reg.exe query or Win32 RegOpenKeyExW without extra registry dependency
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    Command::new("reg.exe")
        .args(["query", &format!("HKLM\\{subkey}")])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .is_ok_and(|o| o.status.success())
}

use std::process::Command;

fn align_up(v: usize, align: usize) -> usize {
    (v + align - 1) & !(align - 1)
}

fn rgba_to_nv12(width: u32, height: u32, rgba: &[u8], out: &mut Vec<u8>) {
    let w = (width & !1) as usize;
    let h = (height & !1) as usize;
    let stride = (width as usize) * 4;
    let y_len = w * h;
    let uv_len = y_len / 2;
    out.resize(y_len + uv_len, 0);

    let (y_plane, uv_plane) = out.split_at_mut(y_len);
    for y in 0..h {
        let row = &rgba[y * stride..];
        for x in 0..w {
            let p = &row[x * 4..x * 4 + 4];
            let r = p[0] as i32;
            let g = p[1] as i32;
            let b = p[2] as i32;
            let yv = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
            y_plane[y * w + x] = yv.clamp(0, 255) as u8;
        }
    }
    for y in (0..h).step_by(2) {
        let row = &rgba[y * stride..];
        let uv_row = &mut uv_plane[(y / 2) * w..];
        for x in (0..w).step_by(2) {
            let p = &row[x * 4..x * 4 + 4];
            let r = p[0] as i32;
            let g = p[1] as i32;
            let b = p[2] as i32;
            let u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
            let v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
            uv_row[x] = u.clamp(0, 255) as u8;
            uv_row[x + 1] = v.clamp(0, 255) as u8;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vcam_status_never_panics_without_admin() {
        let st = probe_vcam_status(false);
        assert!(!st.message.is_empty());
    }
}
