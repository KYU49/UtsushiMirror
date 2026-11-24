use rosc::{OscMessage, OscPacket, OscType};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Normalized bone pose received via VMC Protocol (`/VMC/Ext/Bone/Pos`).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct VmcBonePose {
    pub pos: [f32; 3],
    pub quat: [f32; 4], // x, y, z, w
}

/// Root transform received via `/VMC/Ext/Root/Pos`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct VmcRootPose {
    pub pos: [f32; 3],
    pub quat: [f32; 4],
}

/// Camera transform received via `/VMC/Ext/Cam`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct VmcCamera {
    pub pos: [f32; 3],
    pub quat: [f32; 4],
    pub fov_deg: f32,
}

/// Coalesced frame snapshot forwarded from OSC/VMC receiver to Godot (or encoded for send).
#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct VmcFrame {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub root: Option<VmcRootPose>,
    #[serde(default)]
    pub bones: BTreeMap<String, VmcBonePose>,
    #[serde(default)]
    pub blendshapes: BTreeMap<String, f32>,
    #[serde(default)]
    pub blend_apply: bool,
    #[serde(default)]
    pub blend_dirty: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub camera: Option<VmcCamera>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ok: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub time: Option<f32>,
    #[serde(default)]
    pub seq: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum VmcEvent {
    Ok {
        value: i32,
    },
    Time {
        time_sec: f32,
    },
    RootPos {
        name: String,
        pos: [f32; 3],
        quat: [f32; 4],
    },
    BonePos {
        name: String,
        pos: [f32; 3],
        quat: [f32; 4],
    },
    BlendVal {
        name: String,
        value: f32,
    },
    BlendApply,
    Cam {
        name: String,
        pos: [f32; 3],
        quat: [f32; 4],
        fov_deg: f32,
    },
}

fn as_i32(t: &OscType) -> Option<i32> {
    match *t {
        OscType::Int(v) => Some(v),
        OscType::Long(v) => Some(v as i32),
        OscType::Float(v) => Some(v as i32),
        OscType::Bool(v) => Some(if v { 1 } else { 0 }),
        _ => None,
    }
}

fn as_f32(t: &OscType) -> Option<f32> {
    match *t {
        OscType::Float(v) => Some(v),
        OscType::Double(v) => Some(v as f32),
        OscType::Int(v) => Some(v as f32),
        _ => None,
    }
}

fn as_str(t: &OscType) -> Option<&str> {
    match t {
        OscType::String(s) => Some(s.as_str()),
        _ => None,
    }
}

/// Decodes an incoming UDP OSC packet (single message or bundle) into VMC events.
pub fn decode_osc_packet(bytes: &[u8]) -> Result<Vec<VmcEvent>, rosc::OscError> {
    let (_, packet) = rosc::decoder::decode_udp(bytes)?;
    let mut out = Vec::new();
    collect_packet(&packet, &mut out);
    Ok(out)
}

fn collect_packet(packet: &OscPacket, out: &mut Vec<VmcEvent>) {
    match packet {
        OscPacket::Message(msg) => {
            if let Some(ev) = decode_message(msg) {
                out.push(ev);
            }
        }
        OscPacket::Bundle(bundle) => {
            for item in &bundle.content {
                collect_packet(item, out);
            }
        }
    }
}

fn decode_message(msg: &OscMessage) -> Option<VmcEvent> {
    let args = &msg.args;
    match msg.addr.as_str() {
        "/VMC/Ext/OK" if !args.is_empty() => {
            let value = as_i32(&args[0])?;
            Some(VmcEvent::Ok { value })
        }
        "/VMC/Ext/T" if !args.is_empty() => {
            let time_sec = as_f32(&args[0])?;
            Some(VmcEvent::Time { time_sec })
        }
        "/VMC/Ext/Root/Pos" if args.len() >= 8 => {
            let name = as_str(&args[0])?.to_string();
            let pos = [as_f32(&args[1])?, as_f32(&args[2])?, as_f32(&args[3])?];
            let quat = [
                as_f32(&args[4])?,
                as_f32(&args[5])?,
                as_f32(&args[6])?,
                as_f32(&args[7])?,
            ];
            Some(VmcEvent::RootPos { name, pos, quat })
        }
        "/VMC/Ext/Bone/Pos" if args.len() >= 8 => {
            let name = as_str(&args[0])?.to_string();
            let pos = [as_f32(&args[1])?, as_f32(&args[2])?, as_f32(&args[3])?];
            let quat = [
                as_f32(&args[4])?,
                as_f32(&args[5])?,
                as_f32(&args[6])?,
                as_f32(&args[7])?,
            ];
            Some(VmcEvent::BonePos { name, pos, quat })
        }
        "/VMC/Ext/Blend/Val" if args.len() >= 2 => {
            let name = as_str(&args[0])?.to_string();
            let value = as_f32(&args[1])?;
            Some(VmcEvent::BlendVal { name, value })
        }
        "/VMC/Ext/Blend/Apply" => Some(VmcEvent::BlendApply),
        "/VMC/Ext/Cam" if args.len() >= 9 => {
            let name = as_str(&args[0])?.to_string();
            let pos = [as_f32(&args[1])?, as_f32(&args[2])?, as_f32(&args[3])?];
            let quat = [
                as_f32(&args[4])?,
                as_f32(&args[5])?,
                as_f32(&args[6])?,
                as_f32(&args[7])?,
            ];
            let fov_deg = as_f32(&args[8])?;
            Some(VmcEvent::Cam {
                name,
                pos,
                quat,
                fov_deg,
            })
        }
        _ => None,
    }
}

/// Applies decoded VMC events into a coalesced VmcFrame.
pub fn apply_vmc_events(frame: &mut VmcFrame, events: &[VmcEvent]) {
    for ev in events {
        match ev {
            VmcEvent::Ok { value } => {
                frame.ok = Some(*value);
            }
            VmcEvent::Time { time_sec } => {
                frame.time = Some(*time_sec);
            }
            VmcEvent::RootPos { pos, quat, .. } => {
                frame.root = Some(VmcRootPose {
                    pos: *pos,
                    quat: *quat,
                });
            }
            VmcEvent::BonePos { name, pos, quat } => {
                frame.bones.insert(
                    name.clone(),
                    VmcBonePose {
                        pos: *pos,
                        quat: *quat,
                    },
                );
            }
            VmcEvent::BlendVal { name, value } => {
                frame.blendshapes.insert(name.clone(), *value);
                frame.blend_dirty = true;
            }
            VmcEvent::BlendApply => {
                frame.blend_apply = true;
            }
            VmcEvent::Cam {
                pos, quat, fov_deg, ..
            } => {
                frame.camera = Some(VmcCamera {
                    pos: *pos,
                    quat: *quat,
                    fov_deg: *fov_deg,
                });
            }
        }
    }
    if !events.is_empty() {
        frame.seq = frame.seq.wrapping_add(1);
    }
}

/// Encodes a VmcFrame into chunked OSC bundles following VMC Protocol (/VMC/Ext/*).
pub fn encode_vmc_bundles(
    frame: &VmcFrame,
    time_sec: f32,
    max_msgs_per_bundle: usize,
) -> Result<Vec<Vec<u8>>, rosc::OscError> {
    let mut msgs: Vec<OscPacket> = Vec::new();
    msgs.push(OscPacket::Message(OscMessage {
        addr: "/VMC/Ext/OK".into(),
        args: vec![OscType::Int(frame.ok.unwrap_or(1))],
    }));
    msgs.push(OscPacket::Message(OscMessage {
        addr: "/VMC/Ext/T".into(),
        args: vec![OscType::Float(time_sec)],
    }));
    if let Some(root) = &frame.root {
        msgs.push(OscPacket::Message(OscMessage {
            addr: "/VMC/Ext/Root/Pos".into(),
            args: vec![
                OscType::String("root".into()),
                OscType::Float(root.pos[0]),
                OscType::Float(root.pos[1]),
                OscType::Float(root.pos[2]),
                OscType::Float(root.quat[0]),
                OscType::Float(root.quat[1]),
                OscType::Float(root.quat[2]),
                OscType::Float(root.quat[3]),
            ],
        }));
    }
    for (name, pose) in &frame.bones {
        msgs.push(OscPacket::Message(OscMessage {
            addr: "/VMC/Ext/Bone/Pos".into(),
            args: vec![
                OscType::String(name.clone()),
                OscType::Float(pose.pos[0]),
                OscType::Float(pose.pos[1]),
                OscType::Float(pose.pos[2]),
                OscType::Float(pose.quat[0]),
                OscType::Float(pose.quat[1]),
                OscType::Float(pose.quat[2]),
                OscType::Float(pose.quat[3]),
            ],
        }));
    }
    for (name, val) in &frame.blendshapes {
        msgs.push(OscPacket::Message(OscMessage {
            addr: "/VMC/Ext/Blend/Val".into(),
            args: vec![OscType::String(name.clone()), OscType::Float(*val)],
        }));
    }
    if !frame.blendshapes.is_empty() || frame.blend_apply {
        msgs.push(OscPacket::Message(OscMessage {
            addr: "/VMC/Ext/Blend/Apply".into(),
            args: vec![],
        }));
    }
    if let Some(cam) = &frame.camera {
        msgs.push(OscPacket::Message(OscMessage {
            addr: "/VMC/Ext/Cam".into(),
            args: vec![
                OscType::String("Camera".into()),
                OscType::Float(cam.pos[0]),
                OscType::Float(cam.pos[1]),
                OscType::Float(cam.pos[2]),
                OscType::Float(cam.quat[0]),
                OscType::Float(cam.quat[1]),
                OscType::Float(cam.quat[2]),
                OscType::Float(cam.quat[3]),
                OscType::Float(cam.fov_deg),
            ],
        }));
    }

    let chunk_size = max_msgs_per_bundle.max(1);
    let mut out = Vec::with_capacity(msgs.len().div_ceil(chunk_size));
    for chunk in msgs.chunks(chunk_size) {
        let bundle = OscPacket::Bundle(rosc::OscBundle {
            timetag: rosc::OscTime {
                seconds: 0,
                fractional: 1,
            },
            content: chunk.to_vec(),
        });
        out.push(rosc::encoder::encode(&bundle)?);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rosc::{OscBundle, OscTime};

    #[test]
    fn decodes_vmc_bundle() {
        let bone_msg = OscPacket::Message(OscMessage {
            addr: "/VMC/Ext/Bone/Pos".into(),
            args: vec![
                OscType::String("Head".into()),
                OscType::Float(0.0),
                OscType::Float(1.4),
                OscType::Float(0.0),
                OscType::Float(0.0),
                OscType::Float(0.1),
                OscType::Float(0.0),
                OscType::Float(0.995),
            ],
        });
        let blend_msg = OscPacket::Message(OscMessage {
            addr: "/VMC/Ext/Blend/Val".into(),
            args: vec![OscType::String("happy".into()), OscType::Float(0.75)],
        });
        let apply_msg = OscPacket::Message(OscMessage {
            addr: "/VMC/Ext/Blend/Apply".into(),
            args: vec![],
        });
        let bundle = OscPacket::Bundle(OscBundle {
            timetag: OscTime {
                seconds: 0,
                fractional: 1,
            },
            content: vec![bone_msg, blend_msg, apply_msg],
        });
        let bytes = rosc::encoder::encode(&bundle).unwrap();
        let events = decode_osc_packet(&bytes).unwrap();
        assert_eq!(events.len(), 3);

        let mut frame = VmcFrame::default();
        apply_vmc_events(&mut frame, &events);
        assert!(frame.bones.contains_key("Head"));
        assert_eq!(frame.blendshapes.get("happy"), Some(&0.75));
        assert!(frame.blend_apply);
        assert!(frame.blend_dirty);
        assert_eq!(frame.seq, 1);
    }

    #[test]
    fn roundtrips_vmc_encode_decode() {
        let mut src = VmcFrame {
            root: Some(VmcRootPose {
                pos: [0.1, 0.2, -0.3],
                quat: [0.0, 0.25, 0.0, 0.968],
            }),
            bones: BTreeMap::from([(
                "LeftUpperArm".to_string(),
                VmcBonePose {
                    pos: [0.0, 0.0, 0.0],
                    quat: [0.1, -0.2, 0.3, 0.927],
                },
            )]),
            blendshapes: BTreeMap::from([("Joy".to_string(), 0.85)]),
            blend_apply: true,
            blend_dirty: false,
            camera: Some(VmcCamera {
                pos: [0.0, 1.4, -2.0],
                quat: [0.0, 0.0, 0.0, 1.0],
                fov_deg: 35.0,
            }),
            ok: Some(1),
            time: Some(1.5),
            seq: 0,
        };
        let bundles = encode_vmc_bundles(&src, 1.5, 4).unwrap();
        assert!(bundles.len() >= 2);

        let mut dst = VmcFrame::default();
        for b in &bundles {
            let evs = decode_osc_packet(b).unwrap();
            apply_vmc_events(&mut dst, &evs);
        }
        src.seq = dst.seq;
        src.blend_dirty = dst.blend_dirty;
        assert_eq!(dst, src);
    }
}
