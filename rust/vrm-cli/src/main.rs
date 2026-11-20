use anyhow::{anyhow, Context, Result};
use base64::Engine;
use clap::{Parser, Subcommand};
use rosc::{OscBundle, OscMessage, OscPacket, OscTime, OscType};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::net::UdpSocket;
use tungstenite::{connect, Message};
use vrm_protocol::{RpcRequest, RpcResponse, TimelineSequence};

#[derive(Parser)]
#[command(name = "vrmviewer-cli", version, about = "CLI controller for UtsushiMirror")]
struct Cli {
    #[arg(long)]
    ws_url: Option<String>,
    #[arg(long)]
    osc_addr: Option<String>,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Ping,
    Status,
    ModelInfo,
    Shutdown,
    Load {
        path: String,
    },
    Unload,
    Camera {
        #[arg(long)]
        preset: Option<String>,
        #[arg(long)]
        yaw: Option<f32>,
        #[arg(long)]
        pitch: Option<f32>,
        #[arg(long)]
        distance: Option<f32>,
        #[arg(long, value_parser = parse_vec3)]
        target: Option<[f32; 3]>,
        #[arg(long)]
        fov: Option<f32>,
        #[arg(long)]
        ortho: Option<bool>,
    },
    Light {
        #[arg(long)]
        preset: Option<String>,
        #[arg(long)]
        key_azimuth: Option<f32>,
        #[arg(long)]
        key_elevation: Option<f32>,
        #[arg(long)]
        key_energy: Option<f32>,
        #[arg(long)]
        key_color: Option<String>,
        #[arg(long)]
        fill_energy: Option<f32>,
        #[arg(long)]
        rim_energy: Option<f32>,
        #[arg(long)]
        ambient_energy: Option<f32>,
        #[arg(long)]
        shadows: Option<bool>,
        #[arg(long)]
        bloom: Option<bool>,
        #[arg(long)]
        tonemap: Option<String>,
        #[arg(long, value_parser = parse_vec3)]
        wind: Option<[f32; 3]>,
    },
    Anim {
        #[command(subcommand)]
        sub: AnimCmd,
    },
    Expr {
        #[command(subcommand)]
        sub: ExprCmd,
    },
    Bone {
        #[command(subcommand)]
        sub: BoneCmd,
    },
    Lookat {
        #[arg(long)]
        mode: Option<String>,
        #[arg(long, value_parser = parse_vec3)]
        target: Option<[f32; 3]>,
    },
    FirstPerson {
        enabled: bool,
    },
    Bg {
        #[arg(long)]
        mode: Option<String>,
        #[arg(long)]
        color: Option<String>,
        #[arg(long)]
        gradient_bottom: Option<String>,
        #[arg(long)]
        image: Option<String>,
    },
    Window {
        #[arg(long)]
        transparent: Option<bool>,
        #[arg(long)]
        borderless: Option<bool>,
        #[arg(long)]
        always_on_top: Option<bool>,
        #[arg(long)]
        click_through: Option<bool>,
        #[arg(long)]
        settings_visible: Option<bool>,
        #[arg(long, value_parser = parse_size)]
        size: Option<[i32; 2]>,
    },
    Output {
        #[arg(long)]
        width: Option<u32>,
        #[arg(long)]
        height: Option<u32>,
        #[arg(long)]
        bg_mode: Option<String>,
        #[arg(long)]
        color: Option<String>,
        #[arg(long)]
        image: Option<String>,
    },
    Screenshot {
        #[arg(long)]
        output: Option<String>,
        #[arg(long)]
        transparent: Option<bool>,
        #[arg(long)]
        width: Option<u32>,
        #[arg(long)]
        height: Option<u32>,
        #[arg(long)]
        base64: bool,
    },
    Record {
        #[command(subcommand)]
        sub: RecordCmd,
    },
    RenderSequence {
        sequence_json: String,
    },
    Spout {
        #[arg(long, conflicts_with = "disable")]
        enable: bool,
        #[arg(long, conflicts_with = "enable")]
        disable: bool,
        #[arg(long)]
        name: Option<String>,
    },
    Vcam {
        #[command(subcommand)]
        sub: VcamCmd,
    },
    VmcSend {
        #[arg(long, default_value = "Head")]
        bone: String,
        #[arg(long, default_value_t = 0.0)]
        rx_deg: f32,
        #[arg(long, default_value_t = 20.0)]
        ry_deg: f32,
        #[arg(long, default_value_t = 0.0)]
        rz_deg: f32,
        #[arg(long, default_value = "happy")]
        expr: String,
        #[arg(long, default_value_t = 0.8)]
        val: f32,
    },
    Config {
        #[command(subcommand)]
        sub: ConfigCmd,
    },
    Rpc {
        method: String,
        #[arg(default_value = "{}")]
        params_json: String,
    },
}

#[derive(Subcommand)]
enum AnimCmd {
    Load {
        path: String,
        #[arg(long)]
        name: Option<String>,
        #[arg(long)]
        auto_play: bool,
    },
    Play {
        name: String,
        #[arg(long, default_value_t = true)]
        looping: bool,
        #[arg(long, default_value_t = 1.0)]
        speed: f32,
        #[arg(long, default_value_t = 0.25)]
        blend: f32,
    },
    Stop,
    List,
    Params {
        #[arg(long)]
        speed: Option<f32>,
        #[arg(long)]
        looping: Option<bool>,
        #[arg(long)]
        paused: Option<bool>,
        #[arg(long)]
        seek_sec: Option<f32>,
    },
    Idle {
        #[arg(long)]
        enabled: Option<bool>,
        #[arg(long)]
        breathing: Option<bool>,
        #[arg(long)]
        blink: Option<bool>,
        #[arg(long)]
        saccade: Option<bool>,
        #[arg(long)]
        sway: Option<bool>,
        #[arg(long)]
        intensity: Option<f32>,
    },
}

#[derive(Subcommand)]
enum ExprCmd {
    Set {
        name: String,
        weight: f32,
        #[arg(long, default_value_t = 0.0)]
        transition: f32,
    },
    Multi {
        weights_json: String,
        #[arg(long, default_value_t = 0.0)]
        transition: f32,
        #[arg(long)]
        reset_others: bool,
    },
    Reset {
        #[arg(long, default_value_t = 0.0)]
        transition: f32,
    },
    List,
}

#[derive(Subcommand)]
enum BoneCmd {
    Set {
        bone_name: String,
        rx_deg: f32,
        ry_deg: f32,
        rz_deg: f32,
        #[arg(long)]
        clear_others: bool,
    },
    Reset,
}

#[derive(Subcommand)]
enum RecordCmd {
    Start {
        #[arg(long)]
        output: Option<String>,
        #[arg(long, default_value = "mp4")]
        format: String,
        #[arg(long, default_value_t = 60)]
        fps: u32,
        #[arg(long)]
        width: Option<u32>,
        #[arg(long)]
        height: Option<u32>,
    },
    Stop,
}

#[derive(Subcommand)]
enum VcamCmd {
    Status,
    Enable,
    Disable,
    RegisterHelp,
}

#[derive(Subcommand)]
enum ConfigCmd {
    Save { path: Option<String> },
    Load { path: Option<String> },
}

fn parse_vec3(s: &str) -> Result<[f32; 3], String> {
    let parts: Vec<&str> = s.split(',').collect();
    if parts.len() != 3 {
        return Err("Expected x,y,z".into());
    }
    Ok([
        parts[0].trim().parse::<f32>().map_err(|e| e.to_string())?,
        parts[1].trim().parse::<f32>().map_err(|e| e.to_string())?,
        parts[2].trim().parse::<f32>().map_err(|e| e.to_string())?,
    ])
}

fn parse_size(s: &str) -> Result<[i32; 2], String> {
    let parts: Vec<&str> = s.split('x').collect();
    if parts.len() != 2 {
        return Err("Expected WxH (e.g. 1280x720)".into());
    }
    Ok([
        parts[0].trim().parse::<i32>().map_err(|e| e.to_string())?,
        parts[1].trim().parse::<i32>().map_err(|e| e.to_string())?,
    ])
}

fn call_ws(ws_url: &str, method: &str, params: Value) -> Result<Value> {
    let (mut socket, _) =
        connect(ws_url).with_context(|| format!("Failed to connect to {ws_url} (is UtsushiMirror running?)"))?;
    let req = RpcRequest::new(1, method, params);
    socket.send(Message::Text(serde_json::to_string(&req)?.into()))?;
    loop {
        match socket.read()? {
            Message::Text(txt) => {
                let resp: RpcResponse = serde_json::from_str(&txt)?;
                let _ = socket.close(None);
                if let Some(err) = resp.error {
                    return Err(anyhow!("RPC error ({}): {}", err.code, err.message));
                }
                return Ok(resp.result.unwrap_or(Value::Null));
            }
            Message::Ping(p) => {
                socket.send(Message::Pong(p))?;
            }
            Message::Close(_) => return Err(anyhow!("Connection closed before RPC response")),
            _ => {}
        }
    }
}

fn abs_or_raw(path: &str) -> String {
    if path.starts_with("res://") || path.starts_with("user://") {
        return path.to_string();
    }
    let p = std::path::Path::new(path);
    if p.is_absolute() {
        return path.to_string();
    }
    if let Ok(canon) = std::fs::canonicalize(p) {
        return canon.to_string_lossy().to_string();
    }
    if let Ok(cwd) = std::env::current_dir() {
        return cwd.join(p).to_string_lossy().to_string();
    }
    path.to_string()
}

fn euler_deg_to_quat(rx_deg: f32, ry_deg: f32, rz_deg: f32) -> [f32; 4] {
    let (rx, ry, rz) = (
        rx_deg.to_radians() * 0.5,
        ry_deg.to_radians() * 0.5,
        rz_deg.to_radians() * 0.5,
    );
    let (sx, cx) = rx.sin_cos();
    let (sy, cy) = ry.sin_cos();
    let (sz, cz) = rz.sin_cos();
    [
        sx * cy * cz + cx * sy * sz,
        cx * sy * cz - sx * cy * sz,
        cx * cy * sz + sx * sy * cz,
        cx * cy * cz - sx * sy * sz,
    ]
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let ws_val = cli.ws_url.unwrap_or_else(|| {
        std::env::var("VRMVIEWER_WS_URL").unwrap_or_else(|_| "ws://127.0.0.1:19100".to_string())
    });
    let osc_val = cli.osc_addr.unwrap_or_else(|| {
        std::env::var("VRMVIEWER_OSC_ADDR").unwrap_or_else(|_| "127.0.0.1:39539".to_string())
    });
    let ws = &ws_val;

    let out: Value = match cli.command {
        Commands::Ping => call_ws(ws, "ping", json!({}))?,
        Commands::Status => call_ws(ws, "get_state", json!({}))?,
        Commands::ModelInfo => call_ws(ws, "get_model_info", json!({}))?,
        Commands::Shutdown => call_ws(ws, "shutdown", json!({}))?,
        Commands::Load { path } => call_ws(ws, "load_vrm", json!({ "path": abs_or_raw(&path) }))?,
        Commands::Unload => call_ws(ws, "unload_vrm", json!({}))?,
        Commands::Camera {
            preset,
            yaw,
            pitch,
            distance,
            target,
            fov,
            ortho,
        } => {
            let mut p = serde_json::Map::new();
            if let Some(v) = preset {
                p.insert("preset".into(), json!(v));
            }
            if let Some(v) = yaw {
                p.insert("yaw_deg".into(), json!(v));
            }
            if let Some(v) = pitch {
                p.insert("pitch_deg".into(), json!(v));
            }
            if let Some(v) = distance {
                p.insert("distance".into(), json!(v));
            }
            if let Some(v) = target {
                p.insert("target".into(), json!(v));
            }
            if let Some(v) = fov {
                p.insert("fov_deg".into(), json!(v));
            }
            if let Some(v) = ortho {
                p.insert("orthographic".into(), json!(v));
            }
            call_ws(ws, "set_camera", Value::Object(p))?
        }
        Commands::Light {
            preset,
            key_azimuth,
            key_elevation,
            key_energy,
            key_color,
            fill_energy,
            rim_energy,
            ambient_energy,
            shadows,
            bloom,
            tonemap,
            wind,
        } => {
            let mut p = serde_json::Map::new();
            if let Some(v) = preset {
                p.insert("preset".into(), json!(v));
            }
            if let Some(v) = key_azimuth {
                p.insert("key_azimuth_deg".into(), json!(v));
            }
            if let Some(v) = key_elevation {
                p.insert("key_elevation_deg".into(), json!(v));
            }
            if let Some(v) = key_energy {
                p.insert("key_energy".into(), json!(v));
            }
            if let Some(v) = key_color {
                p.insert("key_color".into(), json!(v));
            }
            if let Some(v) = fill_energy {
                p.insert("fill_energy".into(), json!(v));
            }
            if let Some(v) = rim_energy {
                p.insert("rim_energy".into(), json!(v));
            }
            if let Some(v) = ambient_energy {
                p.insert("ambient_energy".into(), json!(v));
            }
            if let Some(v) = shadows {
                p.insert("shadows_enabled".into(), json!(v));
            }
            if let Some(v) = bloom {
                p.insert("bloom_enabled".into(), json!(v));
            }
            if let Some(v) = tonemap {
                p.insert("tonemap".into(), json!(v));
            }
            if let Some(v) = wind {
                p.insert("wind".into(), json!(v));
            }
            call_ws(ws, "set_lighting", Value::Object(p))?
        }
        Commands::Anim { sub } => match sub {
            AnimCmd::Load {
                path,
                name,
                auto_play,
            } => call_ws(
                ws,
                "load_vrma",
                json!({ "path": abs_or_raw(&path), "name": name.unwrap_or_default(), "auto_play": auto_play }),
            )?,
            AnimCmd::Play {
                name,
                looping,
                speed,
                blend,
            } => call_ws(
                ws,
                "play_animation",
                json!({ "name": name, "looping": looping, "speed": speed, "blend_sec": blend }),
            )?,
            AnimCmd::Stop => call_ws(ws, "stop_animation", json!({}))?,
            AnimCmd::List => {
                let st = call_ws(ws, "get_state", json!({}))?;
                st.get("available_animations").cloned().unwrap_or(json!([]))
            }
            AnimCmd::Params {
                speed,
                looping,
                paused,
                seek_sec,
            } => call_ws(
                ws,
                "set_animation_params",
                json!({ "speed": speed, "looping": looping, "paused": paused, "seek_sec": seek_sec }),
            )?,
            AnimCmd::Idle {
                enabled,
                breathing,
                blink,
                saccade,
                sway,
                intensity,
            } => {
                let mut p = serde_json::Map::new();
                if let Some(v) = enabled {
                    p.insert("enabled".into(), json!(v));
                }
                if let Some(v) = breathing {
                    p.insert("breathing".into(), json!(v));
                }
                if let Some(v) = blink {
                    p.insert("blink".into(), json!(v));
                }
                if let Some(v) = saccade {
                    p.insert("saccade".into(), json!(v));
                }
                if let Some(v) = sway {
                    p.insert("sway".into(), json!(v));
                }
                if let Some(v) = intensity {
                    p.insert("intensity".into(), json!(v));
                }
                call_ws(ws, "set_idle_params", Value::Object(p))?
            }
        },
        Commands::Expr { sub } => match sub {
            ExprCmd::Set {
                name,
                weight,
                transition,
            } => call_ws(
                ws,
                "set_expression",
                json!({ "name": name, "weight": weight, "transition_sec": transition }),
            )?,
            ExprCmd::Multi {
                weights_json,
                transition,
                reset_others,
            } => {
                let w: BTreeMap<String, f32> = serde_json::from_str(&weights_json)?;
                call_ws(
                    ws,
                    "set_expressions",
                    json!({ "weights": w, "transition_sec": transition, "reset_others": reset_others }),
                )?
            }
            ExprCmd::Reset { transition } => {
                call_ws(ws, "reset_expressions", json!({ "transition_sec": transition }))?
            }
            ExprCmd::List => {
                let st = call_ws(ws, "get_state", json!({}))?;
                st.get("expressions").cloned().unwrap_or(json!({}))
            }
        },
        Commands::Bone { sub } => match sub {
            BoneCmd::Set {
                bone_name,
                rx_deg,
                ry_deg,
                rz_deg,
                clear_others,
            } => {
                let mut bones = serde_json::Map::new();
                bones.insert(
                    bone_name,
                    json!({ "euler_deg": [rx_deg, ry_deg, rz_deg] }),
                );
                call_ws(
                    ws,
                    "set_bones",
                    json!({ "bones": Value::Object(bones), "clear_others": clear_others }),
                )?
            }
            BoneCmd::Reset => call_ws(ws, "reset_bones", json!({}))?,
        },
        Commands::Lookat { mode, target } => call_ws(
            ws,
            "set_lookat",
            json!({ "mode": mode, "target": target }),
        )?,
        Commands::FirstPerson { enabled } => {
            call_ws(ws, "set_first_person", json!({ "enabled": enabled }))?
        }
        Commands::Bg {
            mode,
            color,
            gradient_bottom,
            image,
        } => {
            let mut p = serde_json::Map::new();
            if let Some(v) = mode {
                p.insert("mode".into(), json!(v));
            }
            if let Some(v) = color {
                p.insert("color".into(), json!(v));
            }
            if let Some(v) = gradient_bottom {
                p.insert("gradient_bottom".into(), json!(v));
            }
            if let Some(v) = image {
                p.insert("image_path".into(), json!(abs_or_raw(&v)));
            }
            call_ws(ws, "set_background", Value::Object(p))?
        }
        Commands::Window {
            transparent,
            borderless,
            always_on_top,
            click_through,
            settings_visible,
            size,
        } => {
            let mut p = serde_json::Map::new();
            if let Some(v) = transparent {
                p.insert("transparent".into(), json!(v));
            }
            if let Some(v) = borderless {
                p.insert("borderless".into(), json!(v));
            }
            if let Some(v) = always_on_top {
                p.insert("always_on_top".into(), json!(v));
            }
            if let Some(v) = click_through {
                p.insert("click_through".into(), json!(v));
            }
            if let Some(v) = settings_visible {
                p.insert("settings_visible".into(), json!(v));
            }
            if let Some(v) = size {
                p.insert("size".into(), json!(v));
            }
            call_ws(ws, "set_window", Value::Object(p))?
        }
        Commands::Output {
            width,
            height,
            bg_mode,
            color,
            image,
        } => {
            let mut p = serde_json::Map::new();
            if let Some(v) = width {
                p.insert("width".into(), json!(v));
            }
            if let Some(v) = height {
                p.insert("height".into(), json!(v));
            }
            if let Some(v) = bg_mode {
                p.insert("background_mode".into(), json!(v));
            }
            if let Some(v) = color {
                p.insert("color".into(), json!(v));
            }
            if let Some(v) = image {
                p.insert("image_path".into(), json!(abs_or_raw(&v)));
            }
            call_ws(ws, "set_output_viewport", Value::Object(p))?
        }
        Commands::Screenshot {
            output,
            transparent,
            width,
            height,
            base64,
        } => {
            let mut p = serde_json::Map::new();
            if let Some(v) = output {
                p.insert("output_path".into(), json!(abs_or_raw(&v)));
            }
            if let Some(v) = transparent {
                p.insert("transparent".into(), json!(v));
            }
            if let Some(v) = width {
                p.insert("width".into(), json!(v));
            }
            if let Some(v) = height {
                p.insert("height".into(), json!(v));
            }
            p.insert("return_base64".into(), json!(base64));
            let res = call_ws(ws, "capture_screenshot", Value::Object(p))?;
            if let Some(b64) = res.get("base64_png").and_then(|v| v.as_str()) {
                let bytes = base64::engine::general_purpose::STANDARD.decode(b64)?;
                println!("Screenshot PNG ({} decoded bytes)", bytes.len());
            }
            res
        }
        Commands::Record { sub } => match sub {
            RecordCmd::Start {
                output,
                format,
                fps,
                width,
                height,
            } => call_ws(
                ws,
                "start_recording",
                json!({ "output_path": output.map(|o| abs_or_raw(&o)).unwrap_or_default(), "format": format, "fps": fps, "width": width, "height": height }),
            )?,
            RecordCmd::Stop => call_ws(ws, "stop_recording", json!({}))?,
        },
        Commands::RenderSequence { sequence_json } => {
            let raw = std::fs::read_to_string(&sequence_json)
                .with_context(|| format!("Failed to read {sequence_json}"))?;
            let mut seq: TimelineSequence = serde_json::from_str(&raw)?;
            seq.output_path = abs_or_raw(&seq.output_path);
            if let Some(ref aud) = seq.audio_path {
                seq.audio_path = Some(abs_or_raw(aud));
            }
            call_ws(ws, "render_sequence", serde_json::to_value(seq)?)?
        }
        Commands::Spout {
            enable,
            disable,
            name,
        } => {
            let en = if disable { false } else { enable || true };
            call_ws(
                ws,
                "set_spout",
                json!({ "enabled": en, "sender_name": name }),
            )?
        }
        Commands::Vcam { sub } => match sub {
            VcamCmd::Status => call_ws(ws, "get_vcam_status", json!({}))?,
            VcamCmd::Enable => call_ws(ws, "set_vcam", json!({ "enabled": true }))?,
            VcamCmd::Disable => call_ws(ws, "set_vcam", json!({ "enabled": false }))?,
            VcamCmd::RegisterHelp => {
                json!({
                    "windows": "Run scripts/register_vcam.ps1 as Administrator (or with -Elevate) to register OBS Virtual Camera DirectShow/MediaFoundation CLSID.",
                    "linux": "Install and load v4l2loopback: sudo modprobe v4l2loopback"
                })
            }
        },
        Commands::VmcSend {
            bone,
            rx_deg,
            ry_deg,
            rz_deg,
            expr,
            val,
        } => {
            let q = euler_deg_to_quat(rx_deg, ry_deg, rz_deg);
            let bundle = OscPacket::Bundle(OscBundle {
                timetag: OscTime {
                    seconds: 0,
                    fractional: 1,
                },
                content: vec![
                    OscPacket::Message(OscMessage {
                        addr: "/VMC/Ext/Bone/Pos".into(),
                        args: vec![
                            OscType::String(bone.clone()),
                            OscType::Float(0.0),
                            OscType::Float(0.0),
                            OscType::Float(0.0),
                            OscType::Float(q[0]),
                            OscType::Float(q[1]),
                            OscType::Float(q[2]),
                            OscType::Float(q[3]),
                        ],
                    }),
                    OscPacket::Message(OscMessage {
                        addr: "/VMC/Ext/Blend/Val".into(),
                        args: vec![OscType::String(expr.clone()), OscType::Float(val)],
                    }),
                    OscPacket::Message(OscMessage {
                        addr: "/VMC/Ext/Blend/Apply".into(),
                        args: vec![],
                    }),
                ],
            });
            let bytes = rosc::encoder::encode(&bundle)?;
            let sock = UdpSocket::bind("127.0.0.1:0")?;
            sock.send_to(&bytes, &osc_val)?;
            json!({ "sent_vmc": true, "osc_addr": osc_val, "bone": bone, "expr": expr, "val": val })
        }
        Commands::Config { sub } => match sub {
            ConfigCmd::Save { path } => call_ws(ws, "save_config", json!({ "path": path }))?,
            ConfigCmd::Load { path } => call_ws(ws, "load_config", json!({ "path": path }))?,
        },
        Commands::Rpc {
            method,
            params_json,
        } => {
            let p: Value = serde_json::from_str(&params_json)?;
            call_ws(ws, &method, p)?
        }
    };

    println!("{}", serde_json::to_string_pretty(&out)?);
    Ok(())
}
