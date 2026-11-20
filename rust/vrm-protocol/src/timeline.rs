use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum EasingType {
    #[default]
    Linear,
    EaseIn,
    EaseOut,
    EaseInOut,
    Step,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum VideoFormat {
    #[default]
    Mp4,
    WebmAlpha,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CameraKeyframe {
    pub time_sec: f32,
    #[serde(default)]
    pub easing: EasingType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub yaw_deg: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pitch_deg: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub distance: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target: Option<[f32; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fov_deg: Option<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ExpressionKeyframe {
    pub time_sec: f32,
    #[serde(default)]
    pub easing: EasingType,
    pub weights: BTreeMap<String, f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BonePoseKeyframe {
    pub time_sec: f32,
    #[serde(default)]
    pub easing: EasingType,
    /// Humanoid bone name -> Euler XYZ in degrees.
    #[serde(default)]
    pub bones_euler_deg: BTreeMap<String, [f32; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hips_position: Option<[f32; 3]>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LookAtKeyframe {
    pub time_sec: f32,
    #[serde(default)]
    pub easing: EasingType,
    pub mode: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target: Option<[f32; 3]>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LightingKeyframe {
    pub time_sec: f32,
    #[serde(default)]
    pub easing: EasingType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_azimuth_deg: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_elevation_deg: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_energy: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ambient_energy: Option<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AnimationCue {
    pub time_sec: f32,
    pub name: String,
    #[serde(default = "default_true")]
    pub looping: bool,
    #[serde(default = "default_one")]
    pub speed: f32,
    #[serde(default = "default_blend")]
    pub blend_sec: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct TimelineTracks {
    #[serde(default)]
    pub animations: Vec<AnimationCue>,
    #[serde(default)]
    pub camera: Vec<CameraKeyframe>,
    #[serde(default)]
    pub expressions: Vec<ExpressionKeyframe>,
    #[serde(default)]
    pub bones: Vec<BonePoseKeyframe>,
    #[serde(default)]
    pub lookat: Vec<LookAtKeyframe>,
    #[serde(default)]
    pub lighting: Vec<LightingKeyframe>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TimelineSequence {
    pub output_path: String,
    #[serde(default = "default_fps")]
    pub fps: u32,
    #[serde(default = "default_width")]
    pub width: u32,
    #[serde(default = "default_height")]
    pub height: u32,
    #[serde(default)]
    pub transparent: bool,
    #[serde(default)]
    pub format: VideoFormat,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audio_path: Option<String>,
    pub duration_sec: f32,
    #[serde(default)]
    pub reset_before_start: bool,
    #[serde(default)]
    pub tracks: TimelineTracks,
}

fn default_true() -> bool {
    true
}
fn default_one() -> f32 {
    1.0
}
fn default_blend() -> f32 {
    0.2
}
fn default_fps() -> u32 {
    60
}
fn default_width() -> u32 {
    1280
}
fn default_height() -> u32 {
    720
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timeline_deserializes_with_defaults() {
        let json = r#"{
            "output_path": "out.mp4",
            "duration_sec": 2.5,
            "tracks": {
                "animations": [{"time_sec": 0.0, "name": "walk"}],
                "camera": [{"time_sec": 0.0, "yaw_deg": 0.0, "distance": 2.2}, {"time_sec": 2.5, "yaw_deg": 35.0, "easing": "ease_in_out"}],
                "expressions": [{"time_sec": 0.5, "weights": {"happy": 0.9}}]
            }
        }"#;
        let seq: TimelineSequence = serde_json::from_str(json).unwrap();
        assert_eq!(seq.fps, 60);
        assert_eq!(seq.width, 1280);
        assert_eq!(seq.height, 720);
        assert_eq!(seq.format, VideoFormat::Mp4);
        assert_eq!(seq.tracks.camera.len(), 2);
        assert_eq!(seq.tracks.camera[1].easing, EasingType::EaseInOut);
        assert_eq!(seq.tracks.expressions[0].weights.get("happy"), Some(&0.9));
    }
}
