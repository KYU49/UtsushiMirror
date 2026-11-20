use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct CameraConfig {
    pub yaw_deg: f32,
    pub pitch_deg: f32,
    pub distance: f32,
    pub target: [f32; 3],
    pub fov_deg: f32,
    pub orthographic: bool,
}

impl Default for CameraConfig {
    fn default() -> Self {
        Self {
            yaw_deg: 0.0,
            pitch_deg: 6.0,
            distance: 2.2,
            target: [0.0, 0.95, 0.0],
            fov_deg: 35.0,
            orthographic: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct LightingConfig {
    pub preset: String,
    pub key_azimuth_deg: f32,
    pub key_elevation_deg: f32,
    pub key_energy: f32,
    pub key_color: String,
    pub fill_energy: f32,
    pub fill_color: String,
    pub rim_energy: f32,
    pub rim_color: String,
    pub ambient_energy: f32,
    pub ambient_color: String,
    pub shadows_enabled: bool,
    pub bloom_enabled: bool,
    pub bloom_intensity: f32,
    pub exposure: f32,
    pub tonemap: String,
    pub wind: [f32; 3],
}

impl Default for LightingConfig {
    fn default() -> Self {
        Self {
            preset: "studio".into(),
            key_azimuth_deg: 35.0,
            key_elevation_deg: 30.0,
            key_energy: 1.35,
            key_color: "#fff8f0".into(),
            fill_energy: 0.45,
            fill_color: "#dce8ff".into(),
            rim_energy: 0.65,
            rim_color: "#ffffff".into(),
            ambient_energy: 0.5,
            ambient_color: "#e6ebf5".into(),
            shadows_enabled: true,
            bloom_enabled: false,
            bloom_intensity: 0.25,
            exposure: 1.0,
            tonemap: "filmic".into(),
            wind: [0.0, 0.0, 0.0],
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct BackgroundConfig {
    pub mode: String, // "solid" | "chroma_green" | "chroma_blue" | "gradient" | "image" | "transparent_window"
    pub color: String,
    pub gradient_bottom: String,
    pub image_path: String,
}

impl Default for BackgroundConfig {
    fn default() -> Self {
        Self {
            mode: "solid".into(),
            color: "#1e222b".into(),
            gradient_bottom: "#0f1218".into(),
            image_path: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct WindowConfig {
    pub width: i32,
    pub height: i32,
    pub transparent: bool,
    pub borderless: bool,
    pub always_on_top: bool,
    pub click_through: bool,
    pub settings_visible: bool,
}

impl Default for WindowConfig {
    fn default() -> Self {
        Self {
            width: 1000,
            height: 900,
            transparent: false,
            borderless: false,
            always_on_top: false,
            click_through: false,
            settings_visible: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct OutputConfig {
    pub width: u32,
    pub height: u32,
    pub background_mode: String, // "match_main" | "transparent" | "solid" | "chroma_green" | "image"
    pub color: String,
    pub image_path: String,
    pub spout_enabled: bool,
    pub spout_sender_name: String,
    pub vcam_enabled: bool,
    pub screenshots_dir: String,
    pub recordings_dir: String,
}

impl Default for OutputConfig {
    fn default() -> Self {
        Self {
            width: 1280,
            height: 720,
            background_mode: "transparent".into(),
            color: "#00ff00".into(),
            image_path: String::new(),
            spout_enabled: false,
            spout_sender_name: "UtsushiMirror".into(),
            vcam_enabled: false,
            screenshots_dir: "screenshots".into(),
            recordings_dir: "recordings".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct IdleConfig {
    pub enabled: bool,
    pub breathing: bool,
    pub blink: bool,
    pub saccade: bool,
    pub sway: bool,
    pub intensity: f32,
}

impl Default for IdleConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            breathing: true,
            blink: true,
            saccade: true,
            sway: true,
            intensity: 1.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct HotkeyConfig {
    pub global_enabled: bool,
    pub bindings: BTreeMap<String, String>,
}

impl Default for HotkeyConfig {
    fn default() -> Self {
        let mut bindings = BTreeMap::new();
        bindings.insert("F1".into(), "expr:neutral".into());
        bindings.insert("F2".into(), "expr:happy".into());
        bindings.insert("F3".into(), "expr:angry".into());
        bindings.insert("F4".into(), "expr:sad".into());
        bindings.insert("F5".into(), "expr:relaxed".into());
        bindings.insert("F6".into(), "expr:surprised".into());
        bindings.insert("F7".into(), "expr:aa".into());
        bindings.insert("F8".into(), "expr:ih".into());
        bindings.insert("F9".into(), "expr:ou".into());
        bindings.insert("F10".into(), "expr:blink".into());
        bindings.insert("F11".into(), "action:screenshot".into());
        bindings.insert("F12".into(), "action:toggle_record".into());
        Self {
            global_enabled: false,
            bindings,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct ApiConfig {
    pub ws_port: u16,
    pub osc_port: u16,
}

impl Default for ApiConfig {
    fn default() -> Self {
        Self {
            ws_port: 19100,
            osc_port: 39539,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
#[serde(default)]
pub struct AppConfig {
    pub version: u32,
    pub last_vrm_path: String,
    pub recent_vrm_paths: Vec<String>,
    pub last_animation: String,
    pub first_person: bool,
    pub lookat_mode: String,
    pub camera: CameraConfig,
    pub lighting: LightingConfig,
    pub background: BackgroundConfig,
    pub window: WindowConfig,
    pub output: OutputConfig,
    pub idle: IdleConfig,
    pub hotkeys: HotkeyConfig,
    pub api: ApiConfig,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_roundtrips() {
        let cfg = AppConfig::default();
        let json = serde_json::to_string_pretty(&cfg).unwrap();
        let parsed: AppConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(cfg, parsed);
        assert_eq!(parsed.api.ws_port, 19100);
        assert_eq!(parsed.api.osc_port, 39539);
        assert_eq!(
            parsed.hotkeys.bindings.get("F11"),
            Some(&"action:screenshot".to_string())
        );
    }
}
