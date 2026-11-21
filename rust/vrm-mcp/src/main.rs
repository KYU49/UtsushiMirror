use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};
use tungstenite::{connect, Message};
use vrm_protocol::{RpcRequest, RpcResponse};

#[derive(Debug, Deserialize)]
struct McpRequest {
    #[allow(dead_code)]
    jsonrpc: String,
    #[serde(default)]
    id: Option<Value>,
    method: String,
    #[serde(default)]
    params: Value,
}

#[derive(Debug, Serialize)]
struct McpResponse {
    jsonrpc: &'static str,
    id: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<McpError>,
}

#[derive(Debug, Serialize)]
struct McpError {
    code: i32,
    message: String,
}

impl McpResponse {
    fn ok(id: Value, result: Value) -> Self {
        Self {
            jsonrpc: "2.0",
            id,
            result: Some(result),
            error: None,
        }
    }

    fn err(id: Value, code: i32, message: impl Into<String>) -> Self {
        Self {
            jsonrpc: "2.0",
            id,
            result: None,
            error: Some(McpError {
                code,
                message: message.into(),
            }),
        }
    }
}

fn ws_url() -> String {
    std::env::var("VRMVIEWER_WS_URL").unwrap_or_else(|_| "ws://127.0.0.1:19100".to_string())
}

fn call_viewer(ws: &str, method: &str, params: Value) -> Result<Value> {
    let (mut socket, _) =
        connect(ws).with_context(|| format!("Cannot connect to UtsushiMirror WebSocket at {ws}"))?;
    let req = RpcRequest::new(1, method, params);
    socket.send(Message::Text(serde_json::to_string(&req)?.into()))?;
    loop {
        match socket.read()? {
            Message::Text(txt) => {
                let resp: RpcResponse = serde_json::from_str(&txt)?;
                let _ = socket.close(None);
                if let Some(err) = resp.error {
                    return Err(anyhow!("UtsushiMirror RPC error ({}): {}", err.code, err.message));
                }
                return Ok(resp.result.unwrap_or(Value::Null));
            }
            Message::Ping(p) => socket.send(Message::Pong(p))?,
            Message::Close(_) => return Err(anyhow!("WebSocket closed prematurely")),
            _ => {}
        }
    }
}

fn tool_definitions() -> Value {
    json!([
        {
            "name": "vrm_get_state",
            "description": "Get full live state of UtsushiMirror (loaded model, camera, lighting, animations, expressions, background, outputs, virtual camera status).",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "vrm_get_model_info",
            "description": "Get detailed VRM 1.0 specification metadata (meta, humanBones, expressions, lookAt, nodeConstraints, springBone stats).",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "vrm_load_model",
            "description": "Load a .vrm character file into the viewer.",
            "inputSchema": {
                "type": "object",
                "properties": { "path": { "type": "string", "description": "Path to .vrm file" } },
                "required": ["path"]
            }
        },
        {
            "name": "vrm_unload_model",
            "description": "Unload the current VRM model.",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "vrm_set_camera",
            "description": "Set camera angle, distance, target, FOV, orthographic mode, or framing preset (full_body, bust, face, back, left, right, top_down).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "preset": { "type": "string" },
                    "yaw_deg": { "type": "number" },
                    "pitch_deg": { "type": "number" },
                    "distance": { "type": "number" },
                    "target": { "type": "array", "items": { "type": "number" }, "minItems": 3, "maxItems": 3 },
                    "fov_deg": { "type": "number" },
                    "orthographic": { "type": "boolean" }
                }
            }
        },
        {
            "name": "vrm_set_lighting",
            "description": "Adjust lighting preset (studio, daylight, sunset, dramatic, flat_toon) or key/fill/rim/ambient lights, bloom, exposure, and springBone wind.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "preset": { "type": "string" },
                    "key_azimuth_deg": { "type": "number" },
                    "key_elevation_deg": { "type": "number" },
                    "key_energy": { "type": "number" },
                    "key_color": { "type": "string" },
                    "fill_energy": { "type": "number" },
                    "rim_energy": { "type": "number" },
                    "ambient_energy": { "type": "number" },
                    "shadows_enabled": { "type": "boolean" },
                    "bloom_enabled": { "type": "boolean" },
                    "exposure": { "type": "number" },
                    "wind": { "type": "array", "items": { "type": "number" }, "minItems": 3, "maxItems": 3 }
                }
            }
        },
        {
            "name": "vrm_play_animation",
            "description": "Play a loaded animation by name. Includes bundled .vrma clips (idle, walk, run, sit, Walk_Loop, Idle_Loop, Dance_Loop, ...) and every .vrma / .npz (SMPL motion) placed in the presets folder. Call vrm_get_state and read available_animations for the full list.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "name": { "type": "string" },
                    "looping": { "type": "boolean", "default": true },
                    "speed": { "type": "number", "default": 1.0 },
                    "blend_sec": { "type": "number", "default": 0.25 }
                },
                "required": ["name"]
            }
        },
        {
            "name": "vrm_stop_animation",
            "description": "Stop the current .vrma animation.",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "vrm_set_idle",
            "description": "Configure layered procedural natural idle behaviors (breathing, blink, saccade, sway, intensity).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "enabled": { "type": "boolean" },
                    "breathing": { "type": "boolean" },
                    "blink": { "type": "boolean" },
                    "saccade": { "type": "boolean" },
                    "sway": { "type": "boolean" },
                    "intensity": { "type": "number" }
                }
            }
        },
        {
            "name": "vrm_set_expressions",
            "description": "Set VRM 1.0 expression weights (happy, angry, sad, relaxed, surprised, aa, ih, ou, ee, oh, blink, neutral, or custom expressions).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "weights": { "type": "object", "additionalProperties": { "type": "number" } },
                    "transition_sec": { "type": "number", "default": 0.1 },
                    "reset_others": { "type": "boolean", "default": false }
                },
                "required": ["weights"]
            }
        },
        {
            "name": "vrm_set_lookat",
            "description": "Set eye LookAt mode (camera, manual, off) and optional 3D world target.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "mode": { "type": "string", "enum": ["camera", "manual", "off"] },
                    "target": { "type": "array", "items": { "type": "number" }, "minItems": 3, "maxItems": 3 }
                }
            }
        },
        {
            "name": "vrm_set_bones",
            "description": "Directly pose individual VRM humanoid bones in normalized canonical Euler degrees or quaternions.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "bones": {
                        "type": "object",
                        "description": "Map of boneName -> { euler_deg: [x,y,z] } or { quat_xyzw: [x,y,z,w] }"
                    },
                    "hips_position": { "type": "array", "items": { "type": "number" }, "minItems": 3, "maxItems": 3 },
                    "clear_others": { "type": "boolean", "default": false }
                },
                "required": ["bones"]
            }
        },
        {
            "name": "vrm_reset_pose",
            "description": "Reset all direct bone overrides and expressions back to neutral.",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "vrm_set_background",
            "description": "Set main display background (solid, chroma_green, chroma_blue, gradient, image, transparent_window).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "mode": { "type": "string" },
                    "color": { "type": "string" },
                    "gradient_bottom": { "type": "string" },
                    "image_path": { "type": "string" }
                }
            }
        },
        {
            "name": "vrm_set_window",
            "description": "Control OS window transparency, borderless, always_on_top, click_through, and settings_visible.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "transparent": { "type": "boolean" },
                    "borderless": { "type": "boolean" },
                    "always_on_top": { "type": "boolean" },
                    "click_through": { "type": "boolean" },
                    "settings_visible": { "type": "boolean" }
                }
            }
        },
        {
            "name": "vrm_capture_screenshot",
            "description": "Capture a PNG screenshot of the character and return BOTH the saved path AND the PNG image visually so you can inspect framing, lighting, and pose.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "output_path": { "type": "string" },
                    "transparent": { "type": "boolean", "default": true },
                    "width": { "type": "integer" },
                    "height": { "type": "integer" }
                }
            }
        },
        {
            "name": "vrm_start_recording",
            "description": "Start real-time video recording to MP4 or transparent WebM VP9.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "output_path": { "type": "string" },
                    "format": { "type": "string", "enum": ["mp4", "webm_alpha"], "default": "mp4" },
                    "fps": { "type": "integer", "default": 60 },
                    "width": { "type": "integer" },
                    "height": { "type": "integer" }
                }
            }
        },
        {
            "name": "vrm_stop_recording",
            "description": "Stop active real-time video recording and finalize the output file.",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "vrm_render_sequence",
            "description": "Render a deterministic zero-drop frame-by-frame video sequence (MP4 or transparent WebM) from a JSON timeline of animations, camera, expressions, bones, lookat, lighting keyframes, and optional audio_path.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "output_path": { "type": "string" },
                    "fps": { "type": "integer", "default": 60 },
                    "width": { "type": "integer", "default": 1280 },
                    "height": { "type": "integer", "default": 720 },
                    "transparent": { "type": "boolean", "default": false },
                    "format": { "type": "string", "enum": ["mp4", "webm_alpha"], "default": "mp4" },
                    "audio_path": { "type": "string" },
                    "duration_sec": { "type": "number" },
                    "reset_before_start": { "type": "boolean", "default": false },
                    "tracks": { "type": "object" }
                },
                "required": ["output_path", "duration_sec"]
            }
        },
        {
            "name": "vrm_set_spout",
            "description": "Enable or disable Spout2 GPU texture sharing for OBS Studio.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "enabled": { "type": "boolean" },
                    "sender_name": { "type": "string", "default": "UtsushiMirror" }
                },
                "required": ["enabled"]
            }
        },
        {
            "name": "vrm_set_vcam",
            "description": "Enable or disable Virtual Camera output (Discord/Zoom) or inspect availability.",
            "inputSchema": {
                "type": "object",
                "properties": { "enabled": { "type": "boolean" } },
                "required": ["enabled"]
            }
        },
        {
            "name": "vrm_talk",
            "description": "Move the mouth naturally as if speaking. Give the sentence in `text` (Japanese kana are mapped to the matching mouth shapes; kanji and English get plausible shapes) and/or a length in `duration_sec`. Returns the duration in seconds. Does not play audio.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "text": { "type": "string", "description": "Sentence to speak." },
                    "duration_sec": { "type": "number", "description": "Length in seconds. With text, the speech is stretched to fit; without text, random natural mouth movement." },
                    "speed": { "type": "number", "default": 7.5, "description": "Morae (syllables) per second." },
                    "intensity": { "type": "number", "default": 0.8, "description": "How wide the mouth opens, 0-1." }
                }
            }
        },
        {
            "name": "vrm_stop_talk",
            "description": "Stop the mouth movement started by vrm_talk and close the mouth.",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "vrm_walk",
            "description": "Walk naturally: turn toward the direction, play a walk animation while moving the whole character, then stop (and by default turn to face the camera). Returns the distance and the expected duration in seconds.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "direction": { "type": "string", "enum": ["forward", "backward", "left", "right"], "default": "forward" },
                    "angle_deg": { "type": "number", "description": "Instead of direction: 0 = forward, 90 = right, -90 = left, 180 = backward." },
                    "relative_to": { "type": "string", "enum": ["character", "screen"], "default": "character", "description": "character: directions as seen by the character. screen: as seen on screen (forward = toward the camera)." },
                    "distance": { "type": "number", "default": 1.0, "description": "Meters." },
                    "target": { "type": "array", "items": { "type": "number" }, "minItems": 2, "maxItems": 2, "description": "[x, z] world position to walk to (overrides direction and distance)." },
                    "speed": { "type": "number", "default": 0.8, "description": "Meters per second." },
                    "animation": { "type": "string", "description": "Walk animation name (default: Walk_Loop or walk). Use e.g. Jog_Fwd_Loop or run to jog." },
                    "face_camera_after": { "type": "boolean", "default": true }
                }
            }
        },
        {
            "name": "vrm_stop_walk",
            "description": "Stop walking where the character is now.",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "vrm_apply_shader_preset",
            "description": "Apply a shader preset (.umshader file in the presets folder) by name. vrm_get_state lists them in shader_presets.",
            "inputSchema": {
                "type": "object",
                "properties": { "name": { "type": "string" } },
                "required": ["name"]
            }
        },
        {
            "name": "vrm_save_config",
            "description": "Save current viewer configuration to persistent JSON config.",
            "inputSchema": {
                "type": "object",
                "properties": { "path": { "type": "string" } }
            }
        }
    ])
}

fn handle_tool_call(ws: &str, name: &str, args: Value) -> Result<Value> {
    match name {
        "vrm_get_state" => {
            let v = call_viewer(ws, "get_state", json!({}))?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_get_model_info" => {
            let v = call_viewer(ws, "get_model_info", json!({}))?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_load_model" => {
            let v = call_viewer(ws, "load_vrm", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_unload_model" => {
            let v = call_viewer(ws, "unload_vrm", json!({}))?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_set_camera" => {
            let v = call_viewer(ws, "set_camera", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_set_lighting" => {
            let v = call_viewer(ws, "set_lighting", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_play_animation" => {
            let v = call_viewer(ws, "play_animation", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_stop_animation" => {
            let v = call_viewer(ws, "stop_animation", json!({}))?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_set_idle" => {
            let v = call_viewer(ws, "set_idle_params", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_set_expressions" => {
            let v = call_viewer(ws, "set_expressions", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_set_lookat" => {
            let v = call_viewer(ws, "set_lookat", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_set_bones" => {
            let v = call_viewer(ws, "set_bones", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_reset_pose" => {
            let _ = call_viewer(ws, "reset_bones", json!({}))?;
            let v = call_viewer(ws, "reset_expressions", json!({ "transition_sec": 0.0 }))?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_set_background" => {
            let v = call_viewer(ws, "set_background", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_set_window" => {
            let v = call_viewer(ws, "set_window", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_set_output_viewport" => {
            let v = call_viewer(ws, "set_output_viewport", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_capture_screenshot" => {
            let mut obj = args.as_object().cloned().unwrap_or_default();
            obj.insert("return_base64".into(), json!(true));
            let v = call_viewer(ws, "capture_screenshot", Value::Object(obj))?;
            let mut meta = v.clone();
            let b64_opt = meta
                .as_object_mut()
                .and_then(|m| m.remove("base64_png"))
                .and_then(|x| x.as_str().map(|s| s.to_string()));
            let mut content = vec![json!({
                "type": "text",
                "text": serde_json::to_string_pretty(&meta)?
            })];
            if let Some(b64) = b64_opt {
                content.push(json!({
                    "type": "image",
                    "data": b64,
                    "mimeType": "image/png"
                }));
            }
            Ok(json!({ "content": content }))
        }
        "vrm_start_recording" => {
            let v = call_viewer(ws, "start_recording", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_stop_recording" => {
            let v = call_viewer(ws, "stop_recording", json!({}))?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_render_sequence" => {
            let v = call_viewer(ws, "render_sequence", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_set_spout" => {
            let v = call_viewer(ws, "set_spout", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_set_vcam" => {
            let v = call_viewer(ws, "set_vcam", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_talk" => {
            let v = call_viewer(ws, "talk", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_stop_talk" => {
            let v = call_viewer(ws, "stop_talk", json!({}))?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_walk" => {
            let v = call_viewer(ws, "walk", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_stop_walk" => {
            let v = call_viewer(ws, "stop_walk", json!({}))?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_apply_shader_preset" => {
            let v = call_viewer(ws, "apply_shader_preset", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        "vrm_save_config" => {
            let v = call_viewer(ws, "save_config", args)?;
            Ok(json!({ "content": [{ "type": "text", "text": serde_json::to_string_pretty(&v)? }] }))
        }
        _ => Err(anyhow!("Unknown MCP tool: {name}")),
    }
}

fn process_mcp_line(line: &str, ws: &str) -> Option<McpResponse> {
    let req: McpRequest = match serde_json::from_str(line) {
        Ok(r) => r,
        Err(e) => return Some(McpResponse::err(Value::Null, -32700, format!("Parse error: {e}"))),
    };
    let id = match req.id {
        Some(id) => id,
        None => return None, // JSON-RPC notification (e.g. notifications/initialized)
    };

    let resp = match req.method.as_str() {
        "initialize" => McpResponse::ok(
            id,
            json!({
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {},
                    "resources": {}
                },
                "serverInfo": {
                    "name": "vrmviewer-mcp",
                    "version": env!("CARGO_PKG_VERSION")
                }
            }),
        ),
        "ping" => McpResponse::ok(id, json!({})),
        "tools/list" => McpResponse::ok(id, json!({ "tools": tool_definitions() })),
        "tools/call" => {
            let tool_name = req
                .params
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let args = req
                .params
                .get("arguments")
                .cloned()
                .unwrap_or_else(|| json!({}));
            match handle_tool_call(ws, tool_name, args) {
                Ok(res) => McpResponse::ok(id, res),
                Err(e) => McpResponse::ok(
                    id,
                    json!({
                        "isError": true,
                        "content": [{ "type": "text", "text": format!("{e:#}") }]
                    }),
                ),
            }
        }
        "resources/list" => McpResponse::ok(
            id,
            json!({
                "resources": [{
                    "uri": "vrmviewer://state",
                    "name": "UtsushiMirror Live State",
                    "mimeType": "application/json"
                }]
            }),
        ),
        "resources/read" => {
            let uri = req
                .params
                .get("uri")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            if uri == "vrmviewer://state" {
                match call_viewer(ws, "get_state", json!({})) {
                    Ok(st) => McpResponse::ok(
                        id,
                        json!({
                            "contents": [{
                                "uri": uri,
                                "mimeType": "application/json",
                                "text": serde_json::to_string_pretty(&st).unwrap_or_default()
                            }]
                        }),
                    ),
                    Err(e) => McpResponse::err(id, -32000, format!("{e:#}")),
                }
            } else {
                McpResponse::err(id, -32602, format!("Unknown resource URI: {uri}"))
            }
        }
        other => McpResponse::err(id, -32601, format!("Method not found: {other}")),
    };
    Some(resp)
}

fn main() -> Result<()> {
    let ws = ws_url();
    let stdin = io::stdin();
    let mut stdout = io::stdout().lock();
    for line_res in stdin.lock().lines() {
        let line = line_res?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some(resp) = process_mcp_line(trimmed, &ws) {
            let serialized = serde_json::to_string(&resp)?;
            writeln!(stdout, "{serialized}")?;
            stdout.flush()?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mcp_initialize_and_tools_list() {
        let init_req = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#;
        let resp = process_mcp_line(init_req, "ws://127.0.0.1:19100").unwrap();
        let res = resp.result.unwrap();
        assert_eq!(res["protocolVersion"], "2024-11-05");
        assert_eq!(res["serverInfo"]["name"], "vrmviewer-mcp");

        let notif = r#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#;
        assert!(process_mcp_line(notif, "ws://127.0.0.1:19100").is_none());

        let tools_req = r#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#;
        let tools_resp = process_mcp_line(tools_req, "ws://127.0.0.1:19100")
            .unwrap()
            .result
            .unwrap();
        let arr = tools_resp["tools"].as_array().unwrap();
        assert!(arr.iter().any(|t| t["name"] == "vrm_capture_screenshot"));
        assert!(arr.iter().any(|t| t["name"] == "vrm_render_sequence"));
    }
}
