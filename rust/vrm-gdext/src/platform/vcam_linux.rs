use std::path::Path;

#[derive(Debug, Clone, serde::Serialize)]
pub struct VcamStatus {
    pub available: bool,
    pub active: bool,
    pub backend: String,
    pub requires_admin_registration: bool,
    pub is_admin: bool,
    pub message: String,
}

pub fn probe_vcam_status(active: bool) -> VcamStatus {
    let has_loopback = Path::new("/sys/module/v4l2loopback").exists();
    VcamStatus {
        available: has_loopback,
        active: active && has_loopback,
        backend: "v4l2loopback".into(),
        requires_admin_registration: false,
        is_admin: false,
        message: if has_loopback {
            "v4l2loopback kernel module detected".into()
        } else {
            "v4l2loopback not loaded (run: sudo modprobe v4l2loopback)".into()
        },
    }
}
