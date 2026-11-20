use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

/// JSON-RPC 2.0 Request envelope.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RpcRequest {
    pub jsonrpc: String,
    #[serde(default)]
    pub id: Value,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

impl RpcRequest {
    pub fn new(id: impl Into<Value>, method: impl Into<String>, params: Value) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id: id.into(),
            method: method.into(),
            params,
        }
    }
}

/// JSON-RPC 2.0 Error payload.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

impl RpcError {
    pub fn invalid_params(msg: impl Into<String>) -> Self {
        Self {
            code: -32602,
            message: msg.into(),
            data: None,
        }
    }

    pub fn method_not_found(method: &str) -> Self {
        Self {
            code: -32601,
            message: format!("Method not found: {method}"),
            data: None,
        }
    }

    pub fn internal(msg: impl Into<String>) -> Self {
        Self {
            code: -32603,
            message: msg.into(),
            data: None,
        }
    }
}

/// JSON-RPC 2.0 Response envelope.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RpcResponse {
    pub jsonrpc: String,
    pub id: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
}

impl RpcResponse {
    pub fn ok(id: Value, result: Value) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id,
            result: Some(result),
            error: None,
        }
    }

    pub fn err(id: Value, error: RpcError) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id,
            result: None,
            error: Some(error),
        }
    }
}

/// Internal queued RPC item passed between Rust WebSocket server and Godot main thread.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueuedRpcRequest {
    pub client_id: u64,
    pub id: Value,
    pub method: String,
    pub params: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct LoadVrmParams {
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct CameraParams {
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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub orthographic: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preset: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct LightingParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preset: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_azimuth_deg: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_elevation_deg: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_energy: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_color: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fill_energy: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fill_color: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rim_energy: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rim_color: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ambient_energy: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ambient_color: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub shadows_enabled: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bloom_enabled: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bloom_intensity: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub exposure: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tonemap: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub wind: Option<[f32; 3]>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct LoadVrmaParams {
    pub path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default)]
    pub auto_play: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct PlayAnimationParams {
    pub name: String,
    #[serde(default = "default_true")]
    pub looping: bool,
    #[serde(default = "default_one")]
    pub speed: f32,
    #[serde(default = "default_blend")]
    pub blend_sec: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct AnimationParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub speed: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub looping: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub paused: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub seek_sec: Option<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct IdleParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub breathing: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub blink: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub saccade: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sway: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub intensity: Option<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct SetExpressionParams {
    pub name: String,
    pub weight: f32,
    #[serde(default)]
    pub transition_sec: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct SetExpressionsParams {
    pub weights: BTreeMap<String, f32>,
    #[serde(default)]
    pub transition_sec: f32,
    #[serde(default)]
    pub reset_others: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct LookAtParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>, // "camera" | "manual" | "off"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target: Option<[f32; 3]>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct FirstPersonParams {
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct BoneRotationSpec {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub euler_deg: Option<[f32; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quat_xyzw: Option<[f32; 4]>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct SetBonesParams {
    pub bones: BTreeMap<String, BoneRotationSpec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hips_position: Option<[f32; 3]>,
    #[serde(default)]
    pub clear_others: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct BackgroundParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>, // "solid" | "chroma_green" | "chroma_blue" | "gradient" | "image" | "transparent_window"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gradient_bottom: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct WindowParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transparent: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub borderless: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub always_on_top: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub click_through: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub settings_visible: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<[i32; 2]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub position: Option<[i32; 2]>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct OutputViewportParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub width: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub background_mode: Option<String>, // "match_main" | "transparent" | "solid" | "chroma_green" | "image"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct CaptureScreenshotParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transparent: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub width: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
    #[serde(default)]
    pub return_base64: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct StartRecordingParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_path: Option<String>,
    #[serde(default = "default_format")]
    pub format: String, // "mp4" | "webm_alpha"
    #[serde(default = "default_fps")]
    pub fps: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub width: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct SpoutParams {
    pub enabled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sender_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct VcamParams {
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct HotkeysParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub global_enabled: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bindings: Option<BTreeMap<String, String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct ConfigPathParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
}

fn default_true() -> bool {
    true
}
fn default_one() -> f32 {
    1.0
}
fn default_blend() -> f32 {
    0.25
}
fn default_format() -> String {
    "mp4".to_string()
}
fn default_fps() -> u32 {
    60
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rpc_request_response_roundtrip() {
        let req = RpcRequest::new(
            1,
            "set_expression",
            serde_json::to_value(SetExpressionParams {
                name: "happy".into(),
                weight: 0.85,
                transition_sec: 0.2,
            })
            .unwrap(),
        );
        let json = serde_json::to_string(&req).unwrap();
        let decoded: RpcRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(req, decoded);

        let resp = RpcResponse::ok(decoded.id, serde_json::json!({"applied": true}));
        let resp_json = serde_json::to_string(&resp).unwrap();
        let decoded_resp: RpcResponse = serde_json::from_str(&resp_json).unwrap();
        assert_eq!(resp, decoded_resp);
    }
}
