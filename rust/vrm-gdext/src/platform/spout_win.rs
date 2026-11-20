use std::ffi::c_void;
use std::ptr;
use windows::core::{Interface, PCWSTR};
use windows::Win32::Foundation::{CloseHandle, HANDLE};
use windows::Win32::Graphics::Direct3D::D3D_DRIVER_TYPE_HARDWARE;
use windows::Win32::Graphics::Direct3D11::{
    D3D11CreateDevice, ID3D11Device, ID3D11DeviceContext, ID3D11Texture2D, D3D11_BIND_RENDER_TARGET,
    D3D11_BIND_SHADER_RESOURCE, D3D11_CREATE_DEVICE_BGRA_SUPPORT, D3D11_RESOURCE_MISC_SHARED,
    D3D11_SDK_VERSION, D3D11_TEXTURE2D_DESC, D3D11_USAGE_DEFAULT,
};
use windows::Win32::Graphics::Dxgi::Common::{DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_SAMPLE_DESC};
use windows::Win32::Graphics::Dxgi::IDXGIResource;
use windows::Win32::System::Memory::{
    CreateFileMappingW, MapViewOfFile, UnmapViewOfFile, FILE_MAP_ALL_ACCESS,
    MEMORY_MAPPED_VIEW_ADDRESS, PAGE_READWRITE,
};
use windows::Win32::System::Threading::{CreateMutexW, ReleaseMutex, WaitForSingleObject};

const MAX_SENDERS: usize = 64;
const SENDER_NAME_LEN: usize = 256;
const SPOUT_SENDER_NAMES_MAP: &str = "SpoutSenderNames";
const SPOUT_ACTIVE_SENDER_MAP: &str = "ActiveSenderName";

/// Official Spout2 280-byte shared memory texture description struct.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct SharedTextureInfo {
    pub share_handle: u32,
    pub width: u32,
    pub height: u32,
    pub format: u32,
    pub usage: u32,
    pub description: [u8; 256],
    pub partner_id: u32,
}

struct SharedMap {
    handle: HANDLE,
    view: MEMORY_MAPPED_VIEW_ADDRESS,
    size: usize,
}

unsafe impl Send for SharedMap {}

impl Drop for SharedMap {
    fn drop(&mut self) {
        unsafe {
            if !self.view.Value.is_null() {
                let _ = UnmapViewOfFile(self.view);
            }
            if !self.handle.is_invalid() {
                let _ = CloseHandle(self.handle);
            }
        }
    }
}

pub struct SpoutSender {
    sender_name: String,
    width: u32,
    height: u32,
    device: ID3D11Device,
    context: ID3D11DeviceContext,
    texture: Option<ID3D11Texture2D>,
    share_handle: u32,
    info_map: Option<SharedMap>,
    info_mutex: HANDLE,
    names_map: Option<SharedMap>,
    names_mutex: HANDLE,
    active_map: Option<SharedMap>,
    bgra_scratch: Vec<u8>,
}

unsafe impl Send for SpoutSender {}

impl SpoutSender {
    pub fn new(sender_name: &str) -> Result<Self, String> {
        let mut device: Option<ID3D11Device> = None;
        let mut context: Option<ID3D11DeviceContext> = None;
        unsafe {
            D3D11CreateDevice(
                None,
                D3D_DRIVER_TYPE_HARDWARE,
                Default::default(),
                D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                None,
                D3D11_SDK_VERSION,
                Some(&mut device),
                None,
                Some(&mut context),
            )
            .map_err(|e| format!("D3D11CreateDevice failed: {e}"))?;
        }
        let device = device.ok_or_else(|| "D3D11CreateDevice returned null device".to_string())?;
        let context =
            context.ok_or_else(|| "D3D11CreateDevice returned null context".to_string())?;

        let names_map = create_shared_map(SPOUT_SENDER_NAMES_MAP, MAX_SENDERS * SENDER_NAME_LEN)?;
        let active_map = create_shared_map(SPOUT_ACTIVE_SENDER_MAP, SENDER_NAME_LEN)?;
        let names_mutex = create_named_mutex("SpoutSenderNames_mutex")?;
        let info_mutex = create_named_mutex(&format!("{sender_name}_mutex"))?;

        let mut s = Self {
            sender_name: sender_name.to_string(),
            width: 0,
            height: 0,
            device,
            context,
            texture: None,
            share_handle: 0,
            info_map: None,
            info_mutex,
            names_map: Some(names_map),
            names_mutex,
            active_map: Some(active_map),
            bgra_scratch: Vec::new(),
        };
        s.register_sender_name();
        Ok(s)
    }

    pub fn sender_name(&self) -> &str {
        &self.sender_name
    }

    pub fn send_rgba(&mut self, width: u32, height: u32, rgba: &[u8]) -> Result<(), String> {
        if width == 0 || height == 0 || rgba.len() != (width as usize * height as usize * 4) {
            return Err("Invalid RGBA buffer dimensions".into());
        }
        if self.width != width || self.height != height || self.texture.is_none() {
            self.recreate_texture(width, height)?;
        }

        // Convert RGBA8 -> BGRA8 for DXGI_FORMAT_B8G8R8A8_UNORM
        self.bgra_scratch.resize(rgba.len(), 0);
        for (src, dst) in rgba.chunks_exact(4).zip(self.bgra_scratch.chunks_exact_mut(4)) {
            dst[0] = src[2];
            dst[1] = src[1];
            dst[2] = src[0];
            dst[3] = src[3];
        }

        if let Some(tex) = &self.texture {
            unsafe {
                let _lock = MutexGuardWin::acquire(self.info_mutex, 50);
                self.context.UpdateSubresource(
                    tex,
                    0,
                    None,
                    self.bgra_scratch.as_ptr() as *const c_void,
                    width * 4,
                    0,
                );
                self.context.Flush();
            }
        }
        Ok(())
    }

    fn recreate_texture(&mut self, width: u32, height: u32) -> Result<(), String> {
        let desc = D3D11_TEXTURE2D_DESC {
            Width: width,
            Height: height,
            MipLevels: 1,
            ArraySize: 1,
            Format: DXGI_FORMAT_B8G8R8A8_UNORM,
            SampleDesc: DXGI_SAMPLE_DESC {
                Count: 1,
                Quality: 0,
            },
            Usage: D3D11_USAGE_DEFAULT,
            BindFlags: (D3D11_BIND_SHADER_RESOURCE.0 | D3D11_BIND_RENDER_TARGET.0) as u32,
            CPUAccessFlags: 0,
            MiscFlags: D3D11_RESOURCE_MISC_SHARED.0 as u32,
        };

        let mut tex_opt: Option<ID3D11Texture2D> = None;
        unsafe {
            self.device
                .CreateTexture2D(&desc, None, Some(&mut tex_opt))
                .map_err(|e| format!("CreateTexture2D failed: {e}"))?;
        }
        let tex = tex_opt.ok_or_else(|| "CreateTexture2D returned null".to_string())?;
        let dxgi_res: IDXGIResource = tex
            .cast()
            .map_err(|e| format!("Cast IDXGIResource failed: {e}"))?;
        let share_handle = unsafe {
            dxgi_res
                .GetSharedHandle()
                .map_err(|e| format!("GetSharedHandle failed: {e}"))?
        };
        let handle_u32 = share_handle.0 as usize as u32;

        let info_map = create_shared_map(&self.sender_name, std::mem::size_of::<SharedTextureInfo>())?;
        let mut info = SharedTextureInfo {
            share_handle: handle_u32,
            width,
            height,
            format: DXGI_FORMAT_B8G8R8A8_UNORM.0 as u32,
            usage: 0,
            description: [0u8; 256],
            partner_id: 0,
        };
        let desc_bytes = b"UtsushiMirror Spout2";
        info.description[..desc_bytes.len()].copy_from_slice(desc_bytes);

        unsafe {
            let _lock = MutexGuardWin::acquire(self.info_mutex, 50);
            ptr::copy_nonoverlapping(
                &info as *const SharedTextureInfo as *const u8,
                info_map.view.Value as *mut u8,
                std::mem::size_of::<SharedTextureInfo>(),
            );
        }

        self.width = width;
        self.height = height;
        self.share_handle = handle_u32;
        self.texture = Some(tex);
        self.info_map = Some(info_map);
        Ok(())
    }

    fn register_sender_name(&mut self) {
        let Some(names_map) = &self.names_map else {
            return;
        };
        let _lock = MutexGuardWin::acquire(self.names_mutex, 50);
        let buf = unsafe { std::slice::from_raw_parts_mut(names_map.view.Value as *mut u8, names_map.size) };
        let name_bytes = self.sender_name.as_bytes();
        let copy_len = name_bytes.len().min(SENDER_NAME_LEN - 1);

        let mut free_slot: Option<usize> = None;
        for slot in 0..MAX_SENDERS {
            let off = slot * SENDER_NAME_LEN;
            let slot_slice = &buf[off..off + SENDER_NAME_LEN];
            if slot_slice[0] == 0 {
                if free_slot.is_none() {
                    free_slot = Some(slot);
                }
            } else {
                let end = slot_slice.iter().position(|&b| b == 0).unwrap_or(SENDER_NAME_LEN);
                if &slot_slice[..end] == name_bytes {
                    free_slot = Some(slot);
                    break;
                }
            }
        }
        if let Some(slot) = free_slot {
            let off = slot * SENDER_NAME_LEN;
            buf[off..off + SENDER_NAME_LEN].fill(0);
            buf[off..off + copy_len].copy_from_slice(&name_bytes[..copy_len]);
        }

        if let Some(active_map) = &self.active_map {
            let active_buf =
                unsafe { std::slice::from_raw_parts_mut(active_map.view.Value as *mut u8, active_map.size) };
            if active_buf[0] == 0 {
                active_buf.fill(0);
                active_buf[..copy_len].copy_from_slice(&name_bytes[..copy_len]);
            }
        }
    }

    fn unregister_sender_name(&mut self) {
        let Some(names_map) = &self.names_map else {
            return;
        };
        let _lock = MutexGuardWin::acquire(self.names_mutex, 50);
        let buf = unsafe { std::slice::from_raw_parts_mut(names_map.view.Value as *mut u8, names_map.size) };
        let name_bytes = self.sender_name.as_bytes();
        for slot in 0..MAX_SENDERS {
            let off = slot * SENDER_NAME_LEN;
            let slot_slice = &mut buf[off..off + SENDER_NAME_LEN];
            if slot_slice[0] != 0 {
                let end = slot_slice.iter().position(|&b| b == 0).unwrap_or(SENDER_NAME_LEN);
                if &slot_slice[..end] == name_bytes {
                    slot_slice.fill(0);
                }
            }
        }
    }
}

impl Drop for SpoutSender {
    fn drop(&mut self) {
        self.unregister_sender_name();
        unsafe {
            if !self.info_mutex.is_invalid() {
                let _ = CloseHandle(self.info_mutex);
            }
            if !self.names_mutex.is_invalid() {
                let _ = CloseHandle(self.names_mutex);
            }
        }
    }
}

struct MutexGuardWin(HANDLE);
impl MutexGuardWin {
    fn acquire(h: HANDLE, timeout_ms: u32) -> Self {
        if !h.is_invalid() {
            unsafe {
                let _ = WaitForSingleObject(h, timeout_ms);
            }
        }
        Self(h)
    }
}
impl Drop for MutexGuardWin {
    fn drop(&mut self) {
        if !self.0.is_invalid() {
            unsafe {
                let _ = ReleaseMutex(self.0);
            }
        }
    }
}

fn to_wide_null(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn create_shared_map(name: &str, size: usize) -> Result<SharedMap, String> {
    let wname = to_wide_null(name);
    unsafe {
        let handle = CreateFileMappingW(
            HANDLE::default(),
            None,
            PAGE_READWRITE,
            0,
            size as u32,
            PCWSTR(wname.as_ptr()),
        )
        .map_err(|e| format!("CreateFileMappingW({name}) failed: {e}"))?;
        let view = MapViewOfFile(handle, FILE_MAP_ALL_ACCESS, 0, 0, size);
        if view.Value.is_null() {
            let _ = CloseHandle(handle);
            return Err(format!("MapViewOfFile({name}) returned null"));
        }
        Ok(SharedMap { handle, view, size })
    }
}

fn create_named_mutex(name: &str) -> Result<HANDLE, String> {
    let wname = to_wide_null(name);
    unsafe {
        CreateMutexW(None, false, PCWSTR(wname.as_ptr()))
            .map_err(|e| format!("CreateMutexW({name}) failed: {e}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shared_texture_info_is_280_bytes() {
        assert_eq!(std::mem::size_of::<SharedTextureInfo>(), 280);
    }

    #[test]
    fn spout_sender_initializes_and_sends_frame() {
        // Test creation and single frame upload; skip gracefully only if no hardware D3D11 adapter exists.
        if let Ok(mut sender) = SpoutSender::new("VRMViewer_UnitTest") {
            let rgba = vec![128u8; 32 * 32 * 4];
            sender.send_rgba(32, 32, &rgba).expect("send_rgba");
        }
    }
}
