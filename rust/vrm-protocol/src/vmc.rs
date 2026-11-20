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

/// Coalesced frame snapshot forwarded from OSC/VMC receiver to Godot.
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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub camera: Option<VmcCamera>,
    pub seq: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum VmcEvent {
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
        assert_eq!(frame.seq, 1);
    }
}
