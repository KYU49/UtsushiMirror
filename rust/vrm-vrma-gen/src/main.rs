use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::f32::consts::PI;
use std::fs;
use std::path::Path;

/// Generates 12 spec-compliant VRMC_vrm_animation-1.0 binary `.vrma` files
/// into `assets/animations/` for rig QA and runtime playback.

const SKELETON_LAYOUT: &[(&str, Option<&str>, [f32; 3])] = &[
    ("hips", None, [0.0, 0.90, 0.0]),
    ("spine", Some("hips"), [0.0, 0.12, 0.0]),
    ("chest", Some("spine"), [0.0, 0.14, 0.0]),
    ("upperChest", Some("chest"), [0.0, 0.14, 0.0]),
    ("neck", Some("upperChest"), [0.0, 0.12, 0.0]),
    ("head", Some("neck"), [0.0, 0.08, 0.0]),
    ("leftShoulder", Some("upperChest"), [0.05, 0.10, 0.0]),
    ("leftUpperArm", Some("leftShoulder"), [0.11, 0.0, 0.0]),
    ("leftLowerArm", Some("leftUpperArm"), [0.25, 0.0, 0.0]),
    ("leftHand", Some("leftLowerArm"), [0.23, 0.0, 0.0]),
    ("rightShoulder", Some("upperChest"), [-0.05, 0.10, 0.0]),
    ("rightUpperArm", Some("rightShoulder"), [-0.11, 0.0, 0.0]),
    ("rightLowerArm", Some("rightUpperArm"), [-0.25, 0.0, 0.0]),
    ("rightHand", Some("rightLowerArm"), [-0.23, 0.0, 0.0]),
    ("leftUpperLeg", Some("hips"), [0.09, -0.05, 0.0]),
    ("leftLowerLeg", Some("leftUpperLeg"), [0.0, -0.40, 0.0]),
    ("leftFoot", Some("leftLowerLeg"), [0.0, -0.40, 0.0]),
    ("leftToes", Some("leftFoot"), [0.0, -0.05, 0.10]),
    ("rightUpperLeg", Some("hips"), [-0.09, -0.05, 0.0]),
    ("rightLowerLeg", Some("rightUpperLeg"), [0.0, -0.40, 0.0]),
    ("rightFoot", Some("rightLowerLeg"), [0.0, -0.40, 0.0]),
    ("rightToes", Some("rightFoot"), [0.0, -0.05, 0.10]),
    // Left fingers
    ("leftThumbMetacarpal", Some("leftHand"), [0.03, -0.01, 0.03]),
    ("leftThumbProximal", Some("leftThumbMetacarpal"), [0.03, 0.0, 0.02]),
    ("leftThumbDistal", Some("leftThumbProximal"), [0.02, 0.0, 0.01]),
    ("leftIndexProximal", Some("leftHand"), [0.08, 0.0, 0.02]),
    ("leftIndexIntermediate", Some("leftIndexProximal"), [0.035, 0.0, 0.0]),
    ("leftIndexDistal", Some("leftIndexIntermediate"), [0.025, 0.0, 0.0]),
    ("leftMiddleProximal", Some("leftHand"), [0.085, 0.0, 0.0]),
    ("leftMiddleIntermediate", Some("leftMiddleProximal"), [0.038, 0.0, 0.0]),
    ("leftMiddleDistal", Some("leftMiddleIntermediate"), [0.025, 0.0, 0.0]),
    ("leftRingProximal", Some("leftHand"), [0.08, 0.0, -0.02]),
    ("leftRingIntermediate", Some("leftRingProximal"), [0.035, 0.0, 0.0]),
    ("leftRingDistal", Some("leftRingIntermediate"), [0.022, 0.0, 0.0]),
    ("leftLittleProximal", Some("leftHand"), [0.075, 0.0, -0.035]),
    ("leftLittleIntermediate", Some("leftLittleProximal"), [0.028, 0.0, 0.0]),
    ("leftLittleDistal", Some("leftLittleIntermediate"), [0.02, 0.0, 0.0]),
    // Right fingers
    ("rightThumbMetacarpal", Some("rightHand"), [-0.03, -0.01, 0.03]),
    ("rightThumbProximal", Some("rightThumbMetacarpal"), [-0.03, 0.0, 0.02]),
    ("rightThumbDistal", Some("rightThumbProximal"), [-0.02, 0.0, 0.01]),
    ("rightIndexProximal", Some("rightHand"), [-0.08, 0.0, 0.02]),
    ("rightIndexIntermediate", Some("rightIndexProximal"), [-0.035, 0.0, 0.0]),
    ("rightIndexDistal", Some("rightIndexIntermediate"), [-0.025, 0.0, 0.0]),
    ("rightMiddleProximal", Some("rightHand"), [-0.085, 0.0, 0.0]),
    ("rightMiddleIntermediate", Some("rightMiddleProximal"), [-0.038, 0.0, 0.0]),
    ("rightMiddleDistal", Some("rightMiddleIntermediate"), [-0.025, 0.0, 0.0]),
    ("rightRingProximal", Some("rightHand"), [-0.08, 0.0, -0.02]),
    ("rightRingIntermediate", Some("rightRingProximal"), [-0.035, 0.0, 0.0]),
    ("rightRingDistal", Some("rightRingIntermediate"), [-0.022, 0.0, 0.0]),
    ("rightLittleProximal", Some("rightHand"), [-0.075, 0.0, -0.035]),
    ("rightLittleIntermediate", Some("rightLittleProximal"), [-0.028, 0.0, 0.0]),
    ("rightLittleDistal", Some("rightLittleIntermediate"), [-0.02, 0.0, 0.0]),
];

/// Euler XYZ (radians) -> quaternion [x, y, z, w].
fn euler_to_quat(rx: f32, ry: f32, rz: f32) -> [f32; 4] {
    let (sx, cx) = (rx * 0.5).sin_cos();
    let (sy, cy) = (ry * 0.5).sin_cos();
    let (sz, cz) = (rz * 0.5).sin_cos();

    // Intrinsic Y * X * Z or standard XYZ; compose qy * qx * qz for intuitive character angles
    let qx = [sx, 0.0, 0.0, cx];
    let qy = [0.0, sy, 0.0, cy];
    let qz = [0.0, 0.0, sz, cz];
    quat_mul(quat_mul(qy, qx), qz)
}

fn quat_mul(a: [f32; 4], b: [f32; 4]) -> [f32; 4] {
    let [ax, ay, az, aw] = a;
    let [bx, by, bz, bw] = b;
    let x = aw * bx + ax * bw + ay * bz - az * by;
    let y = aw * by - ax * bz + ay * bw + az * bx;
    let z = aw * bz + ax * by - ay * bx + az * bw;
    let w = aw * bw - ax * bx - ay * by - az * bz;
    let len = (x * x + y * y + z * z + w * w).sqrt().max(1e-8);
    [x / len, y / len, z / len, w / len]
}

fn deg(d: f32) -> f32 {
    d * PI / 180.0
}

#[derive(Default)]
struct PoseFrame {
    hips_delta: [f32; 3],
    rotations: BTreeMap<&'static str, [f32; 4]>,
}

impl PoseFrame {
    fn rot(&mut self, bone: &'static str, rx_deg: f32, ry_deg: f32, rz_deg: f32) {
        self.rotations
            .insert(bone, euler_to_quat(deg(rx_deg), deg(ry_deg), deg(rz_deg)));
    }

    fn a_pose_arms(&mut self, angle_deg: f32) {
        self.rot("leftUpperArm", 0.0, 0.0, -angle_deg);
        self.rot("rightUpperArm", 0.0, 0.0, angle_deg);
        self.rot("leftLowerArm", 0.0, -10.0, -6.0);
        self.rot("rightLowerArm", 0.0, 10.0, 6.0);
    }
}

struct ClipSpec {
    name: &'static str,
    duration: f32,
    samples: usize,
    eval: fn(f32) -> PoseFrame,
}

fn eval_t_pose(_u: f32) -> PoseFrame {
    PoseFrame::default()
}

fn eval_a_pose(_u: f32) -> PoseFrame {
    let mut p = PoseFrame::default();
    p.a_pose_arms(45.0);
    p.rot("leftThumbProximal", 0.0, 15.0, 0.0);
    p.rot("rightThumbProximal", 0.0, -15.0, 0.0);
    p
}

fn eval_idle(u: f32) -> PoseFrame {
    let mut p = PoseFrame::default();
    let s = (u * 2.0 * PI).sin();
    let c = (u * 2.0 * PI).cos();
    p.hips_delta = [0.008 * s, 0.004 * c, 0.0];
    p.rot("hips", 0.0, 1.5 * s, 0.8 * s);
    p.rot("spine", 1.0 * c, -1.0 * s, -0.5 * s);
    p.rot("chest", 1.5 * s, 0.0, 0.0);
    p.rot("head", -1.0 * s, 1.5 * c, 0.5 * s);
    p.rot("leftUpperArm", 3.0 * s, 2.0, -48.0 - 1.5 * c);
    p.rot("rightUpperArm", -3.0 * s, -2.0, 48.0 + 1.5 * c);
    p.rot("leftLowerArm", 0.0, -12.0, -8.0);
    p.rot("rightLowerArm", 0.0, 12.0, 8.0);
    p
}

fn eval_walk(u: f32) -> PoseFrame {
    let mut p = PoseFrame::default();
    let ph = u * 2.0 * PI;
    let s = ph.sin();
    let c = ph.cos();
    let bob = (ph * 2.0).cos();

    p.hips_delta = [0.022 * s, -0.025 + 0.022 * bob, 0.0];
    p.rot("hips", 2.0, 5.0 * s, 3.0 * s);
    p.rot("spine", 3.0, -4.0 * s, -1.5 * s);
    p.rot("chest", 2.0, -3.0 * s, 0.0);
    p.rot("head", -3.0, 2.0 * s, 0.0);

    // Legs (opposite swing, slightly outward so knees never clip)
    let l_hip_x = -28.0 * s;
    let r_hip_x = 28.0 * s;
    let l_knee_x = (38.0 * (-c).max(0.0)) + 8.0;
    let r_knee_x = (38.0 * (c).max(0.0)) + 8.0;
    p.rot("leftUpperLeg", l_hip_x, 0.0, 1.5);
    p.rot("rightUpperLeg", r_hip_x, 0.0, -1.5);
    p.rot("leftLowerLeg", l_knee_x, 0.0, 0.0);
    p.rot("rightLowerLeg", r_knee_x, 0.0, 0.0);
    p.rot("leftFoot", -0.3 * l_knee_x + 8.0 * c, 0.0, 0.0);
    p.rot("rightFoot", -0.3 * r_knee_x - 8.0 * c, 0.0, 0.0);

    // Arms (counter swing: when left leg goes forward s>0, left arm goes back +Y and right arm goes forward +Y)
    p.rot("leftUpperArm", 0.0, 24.0 * s, -54.0);
    p.rot("rightUpperArm", 0.0, 24.0 * s, 54.0);
    p.rot("leftLowerArm", 0.0, -18.0 - 10.0 * s.max(0.0), -10.0);
    p.rot("rightLowerArm", 0.0, 18.0 + 10.0 * (-s).max(0.0), 10.0);
    p
}

fn eval_run(u: f32) -> PoseFrame {
    let mut p = PoseFrame::default();
    let ph = u * 2.0 * PI;
    let s = ph.sin();
    let c = ph.cos();
    let bounce = (ph * 2.0).sin();

    p.hips_delta = [0.015 * s, -0.05 + 0.045 * bounce, 0.0];
    p.rot("hips", 12.0, 8.0 * s, 4.0 * s);
    p.rot("spine", 10.0, -8.0 * s, -2.0 * s);
    p.rot("chest", 6.0, -6.0 * s, 0.0);
    p.rot("head", -14.0, 4.0 * s, 0.0);

    let l_hip = -48.0 * s - 10.0;
    let r_hip = 48.0 * s - 10.0;
    let l_knee = 15.0 + 75.0 * (-c).max(0.0);
    let r_knee = 15.0 + 75.0 * (c).max(0.0);
    p.rot("leftUpperLeg", l_hip, 0.0, 1.5);
    p.rot("rightUpperLeg", r_hip, 0.0, -1.5);
    p.rot("leftLowerLeg", l_knee, 0.0, 0.0);
    p.rot("rightLowerLeg", r_knee, 0.0, 0.0);
    p.rot("leftFoot", 12.0 * s, 0.0, 0.0);
    p.rot("rightFoot", -12.0 * s, 0.0, 0.0);

    p.rot("leftUpperArm", 12.0, 45.0 * s, -52.0);
    p.rot("rightUpperArm", 12.0, 45.0 * s, 52.0);
    p.rot("leftLowerArm", 0.0, -82.0, -12.0);
    p.rot("rightLowerArm", 0.0, 82.0, 12.0);
    p
}

fn eval_sit(u: f32) -> PoseFrame {
    let mut p = PoseFrame::default();
    let breath = (u * 2.0 * PI).sin();
    p.hips_delta = [0.0, -0.38, -0.08];
    p.rot("hips", -5.0, 0.0, 0.0);
    p.rot("spine", 4.0 + 1.2 * breath, 0.0, 0.0);
    p.rot("chest", 3.0 + 1.5 * breath, 0.0, 0.0);
    p.rot("head", -3.0 * breath, 2.0 * breath, 0.0);

    // Seated legs (thighs forward -85 deg, knees slightly outward, bent +88 deg)
    p.rot("leftUpperLeg", -85.0, 6.0, 4.0);
    p.rot("rightUpperLeg", -85.0, -6.0, -4.0);
    p.rot("leftLowerLeg", 88.0, 0.0, 0.0);
    p.rot("rightLowerLeg", 88.0, 0.0, 0.0);
    p.rot("leftFoot", -5.0, 0.0, 0.0);
    p.rot("rightFoot", -5.0, 0.0, 0.0);

    // Arms resting comfortably toward lap
    p.rot("leftUpperArm", 18.0, -20.0, -52.0);
    p.rot("rightUpperArm", 18.0, 20.0, 52.0);
    p.rot("leftLowerArm", 0.0, -48.0, -15.0);
    p.rot("rightLowerArm", 0.0, 48.0, 15.0);
    p
}

fn eval_stretch_neck(u: f32) -> PoseFrame {
    let mut p = PoseFrame::default();
    p.a_pose_arms(48.0);
    let ph = u * 2.0 * PI;
    let yaw = 28.0 * ph.sin();
    let roll = 22.0 * (ph * 2.0).sin();
    let pitch = 18.0 * ph.cos();
    p.rot("neck", pitch * 0.4, yaw * 0.4, roll * 0.4);
    p.rot("head", pitch * 0.6, yaw * 0.6, roll * 0.6);
    p
}

fn eval_stretch_shoulder(u: f32) -> PoseFrame {
    let mut p = PoseFrame::default();
    let ph = u * 2.0 * PI;
    let raise = 0.5 - 0.5 * ph.cos(); // 0 -> 1 -> 0
    let arm_z = -45.0 + 125.0 * raise; // -45 down to +80 overhead
    let elbow_bend = 15.0 + 25.0 * raise;
    p.rot("spine", -6.0 * raise, 0.0, 0.0);
    p.rot("chest", -6.0 * raise, 0.0, 0.0);
    p.rot("head", 8.0 * raise, 0.0, 0.0);
    p.rot("leftShoulder", 0.0, 0.0, 12.0 * raise);
    p.rot("rightShoulder", 0.0, 0.0, -12.0 * raise);
    p.rot("leftUpperArm", 0.0, 10.0 * raise, arm_z);
    p.rot("rightUpperArm", 0.0, -10.0 * raise, -arm_z);
    p.rot("leftLowerArm", 0.0, -elbow_bend, 12.0 * raise);
    p.rot("rightLowerArm", 0.0, elbow_bend, -12.0 * raise);
    p
}

fn eval_stretch_side(u: f32) -> PoseFrame {
    let mut p = PoseFrame::default();
    let ph = u * 2.0 * PI;
    let bend = ph.sin(); // -1 (right) .. +1 (left)
    p.rot("spine", 0.0, 0.0, 14.0 * bend);
    p.rot("chest", 0.0, 0.0, 14.0 * bend);
    p.rot("head", 0.0, 0.0, -10.0 * bend);
    // Raise opposite arm overhead while side bending
    let l_raise = (-bend).max(0.0);
    let r_raise = bend.max(0.0);
    p.rot("leftUpperArm", 0.0, 0.0, -48.0 + 130.0 * l_raise);
    p.rot("rightUpperArm", 0.0, 0.0, 48.0 - 130.0 * r_raise);
    p.rot("leftLowerArm", 0.0, -15.0, 20.0 * l_raise);
    p.rot("rightLowerArm", 0.0, 15.0, -20.0 * r_raise);
    p
}

fn eval_stretch_squat(u: f32) -> PoseFrame {
    let mut p = PoseFrame::default();
    let ph = u * 2.0 * PI;
    let d = 0.5 - 0.5 * ph.cos(); // 0..1..0
    p.hips_delta = [0.0, -0.30 * d, -0.05 * d];
    p.rot("hips", 8.0 * d, 0.0, 0.0);
    p.rot("spine", 10.0 * d, 0.0, 0.0);
    p.rot("head", -14.0 * d, 0.0, 0.0);
    // VRM normalized leg axes: +Y/+Z on leftUpperLeg opens knee outward; -Y/-Z on rightUpperLeg opens knee outward
    p.rot("leftUpperLeg", -66.0 * d, 16.0 * d, 10.0 * d);
    p.rot("rightUpperLeg", -66.0 * d, -16.0 * d, -10.0 * d);
    p.rot("leftLowerLeg", 96.0 * d, 0.0, 0.0);
    p.rot("rightLowerLeg", 96.0 * d, 0.0, 0.0);
    p.rot("leftFoot", -30.0 * d, -4.0 * d, -6.0 * d);
    p.rot("rightFoot", -30.0 * d, 4.0 * d, 6.0 * d);
    // Arms forward for balance
    p.rot("leftUpperArm", 0.0, -55.0 * d, -46.0 + 22.0 * d);
    p.rot("rightUpperArm", 0.0, 55.0 * d, 46.0 - 22.0 * d);
    p.rot("leftLowerArm", 0.0, -15.0, -8.0);
    p.rot("rightLowerArm", 0.0, 15.0, 8.0);
    p
}

fn eval_finger_test(u: f32) -> PoseFrame {
    let mut p = PoseFrame::default();
    // Hold hands slightly forward and angled nicely for inspection
    p.rot("leftUpperArm", -20.0, -32.0, -40.0);
    p.rot("rightUpperArm", -20.0, 32.0, 40.0);
    p.rot("leftLowerArm", 0.0, -52.0, 0.0);
    p.rot("rightLowerArm", 0.0, 52.0, 0.0);
    p.rot("leftHand", 0.0, 0.0, 8.0);
    p.rot("rightHand", 0.0, 0.0, -8.0);

    let ph = u * 2.0 * PI;
    let curl = 0.5 - 0.5 * ph.cos(); // 0..1..0
    let c1 = curl * 70.0;
    let c2 = curl * 85.0;
    let c3 = curl * 65.0;
    // Finger flexion toward palm (-Y in T-pose) rotates around -Z on left hand and +Z on right hand
    for b in [
        "leftIndexProximal", "leftMiddleProximal", "leftRingProximal", "leftLittleProximal",
    ] {
        p.rot(b, 0.0, 0.0, -c1);
    }
    for b in [
        "leftIndexIntermediate", "leftMiddleIntermediate", "leftRingIntermediate", "leftLittleIntermediate",
    ] {
        p.rot(b, 0.0, 0.0, -c2);
    }
    for b in [
        "leftIndexDistal", "leftMiddleDistal", "leftRingDistal", "leftLittleDistal",
    ] {
        p.rot(b, 0.0, 0.0, -c3);
    }
    for b in [
        "rightIndexProximal", "rightMiddleProximal", "rightRingProximal", "rightLittleProximal",
    ] {
        p.rot(b, 0.0, 0.0, c1);
    }
    for b in [
        "rightIndexIntermediate", "rightMiddleIntermediate", "rightRingIntermediate", "rightLittleIntermediate",
    ] {
        p.rot(b, 0.0, 0.0, c2);
    }
    for b in [
        "rightIndexDistal", "rightMiddleDistal", "rightRingDistal", "rightLittleDistal",
    ] {
        p.rot(b, 0.0, 0.0, c3);
    }
    p.rot("leftThumbMetacarpal", -8.0 * curl, 46.0 * curl, -18.0 * curl);
    p.rot("leftThumbProximal", -6.0 * curl, 34.0 * curl, -26.0 * curl);
    p.rot("leftThumbDistal", 0.0, 16.0 * curl, -34.0 * curl);
    p.rot("rightThumbMetacarpal", -8.0 * curl, -46.0 * curl, 18.0 * curl);
    p.rot("rightThumbProximal", -6.0 * curl, -34.0 * curl, 26.0 * curl);
    p.rot("rightThumbDistal", 0.0, -16.0 * curl, 34.0 * curl);
    p
}

fn eval_spring_bounce(u: f32) -> PoseFrame {
    let mut p = PoseFrame::default();
    p.a_pose_arms(45.0);
    let ph = u * 2.0 * PI;
    let hop = (ph * 2.0).sin().abs();
    let head_turn = (ph).sin();
    p.hips_delta = [0.06 * head_turn, 0.10 * hop, 0.0];
    p.rot("hips", 0.0, 12.0 * head_turn, 4.0 * head_turn);
    p.rot("head", 8.0 * hop, 24.0 * head_turn, 8.0 * head_turn);
    p.rot("leftUpperLeg", -16.0 * hop, 0.0, 0.0);
    p.rot("rightUpperLeg", -16.0 * hop, 0.0, 0.0);
    p.rot("leftLowerLeg", 28.0 * hop, 0.0, 0.0);
    p.rot("rightLowerLeg", 28.0 * hop, 0.0, 0.0);
    p
}

fn build_vrma_glb(spec: &ClipSpec) -> Vec<u8> {
    let mut bone_to_idx: BTreeMap<&'static str, usize> = BTreeMap::new();
    for (idx, (name, _, _)) in SKELETON_LAYOUT.iter().enumerate() {
        bone_to_idx.insert(*name, idx);
    }

    let mut children_map: Vec<Vec<usize>> = vec![Vec::new(); SKELETON_LAYOUT.len()];
    for (idx, (_, parent_opt, _)) in SKELETON_LAYOUT.iter().enumerate() {
        if let Some(p) = parent_opt {
            if let Some(&p_idx) = bone_to_idx.get(p) {
                children_map[p_idx].push(idx);
            }
        }
    }

    let mut nodes_json = Vec::new();
    let mut human_bones_json = serde_json::Map::new();
    for (idx, (name, _, pos)) in SKELETON_LAYOUT.iter().enumerate() {
        let mut obj = serde_json::Map::new();
        obj.insert("name".into(), json!(name));
        obj.insert("translation".into(), json!(pos));
        if !children_map[idx].is_empty() {
            obj.insert("children".into(), json!(children_map[idx]));
        }
        nodes_json.push(Value::Object(obj));
        human_bones_json.insert((*name).to_string(), json!({ "node": idx }));
    }

    // Evaluate all frames
    let n_samples = spec.samples.max(2);
    let mut times = Vec::with_capacity(n_samples);
    let mut frames = Vec::with_capacity(n_samples);
    for i in 0..n_samples {
        let u = (i as f32) / ((n_samples - 1) as f32);
        times.push(u * spec.duration);
        frames.push((spec.eval)(u));
    }

    // Determine which bones have any non-identity keyframe
    let mut active_bones: Vec<&'static str> = Vec::new();
    for (name, _, _) in SKELETON_LAYOUT {
        if frames.iter().any(|f| f.rotations.contains_key(name)) {
            active_bones.push(*name);
        }
    }
    let has_hips_trans = frames
        .iter()
        .any(|f| f.hips_delta.iter().any(|v| v.abs() > 1e-6));

    // Build BIN chunk + bufferViews + accessors + channels + samplers
    let mut bin_data: Vec<u8> = Vec::new();
    let mut buffer_views = Vec::new();
    let mut accessors = Vec::new();

    let push_f32_slice = |bin: &mut Vec<u8>,
                          bvs: &mut Vec<Value>,
                          accs: &mut Vec<Value>,
                          floats: &[f32],
                          acc_type: &str,
                          count: usize,
                          min_max: Option<([f32; 1], [f32; 1])>|
     -> usize {
        while bin.len() % 4 != 0 {
            bin.push(0);
        }
        let byte_offset = bin.len();
        for f in floats {
            bin.extend_from_slice(&f.to_le_bytes());
        }
        let byte_len = bin.len() - byte_offset;
        let bv_idx = bvs.len();
        bvs.push(json!({
            "buffer": 0,
            "byteOffset": byte_offset,
            "byteLength": byte_len
        }));
        let acc_idx = accs.len();
        let mut acc = json!({
            "bufferView": bv_idx,
            "componentType": 5126,
            "count": count,
            "type": acc_type
        });
        if let Some((mn, mx)) = min_max {
            acc.as_object_mut().unwrap().insert("min".into(), json!(mn));
            acc.as_object_mut().unwrap().insert("max".into(), json!(mx));
        }
        accs.push(acc);
        acc_idx
    };

    let time_acc = push_f32_slice(
        &mut bin_data,
        &mut buffer_views,
        &mut accessors,
        &times,
        "SCALAR",
        n_samples,
        Some(([0.0], [spec.duration])),
    );

    let mut channels = Vec::new();
    let mut samplers = Vec::new();

    if has_hips_trans {
        let mut trans_floats = Vec::with_capacity(n_samples * 3);
        let base_hips = SKELETON_LAYOUT[0].2;
        for f in &frames {
            trans_floats.push(base_hips[0] + f.hips_delta[0]);
            trans_floats.push(base_hips[1] + f.hips_delta[1]);
            trans_floats.push(base_hips[2] + f.hips_delta[2]);
        }
        let trans_acc = push_f32_slice(
            &mut bin_data,
            &mut buffer_views,
            &mut accessors,
            &trans_floats,
            "VEC3",
            n_samples,
            None,
        );
        let samp_idx = samplers.len();
        samplers.push(json!({
            "input": time_acc,
            "interpolation": "LINEAR",
            "output": trans_acc
        }));
        channels.push(json!({
            "sampler": samp_idx,
            "target": { "node": 0, "path": "translation" }
        }));
    }

    for bone_name in &active_bones {
        let node_idx = bone_to_idx[bone_name];
        let mut rot_floats = Vec::with_capacity(n_samples * 4);
        for f in &frames {
            let q = f
                .rotations
                .get(bone_name)
                .copied()
                .unwrap_or([0.0, 0.0, 0.0, 1.0]);
            rot_floats.extend_from_slice(&q);
        }
        let rot_acc = push_f32_slice(
            &mut bin_data,
            &mut buffer_views,
            &mut accessors,
            &rot_floats,
            "VEC4",
            n_samples,
            None,
        );
        let samp_idx = samplers.len();
        samplers.push(json!({
            "input": time_acc,
            "interpolation": "LINEAR",
            "output": rot_acc
        }));
        channels.push(json!({
            "sampler": samp_idx,
            "target": { "node": node_idx, "path": "rotation" }
        }));
    }

    // Ensure at least one channel (e.g. t_pose) so animation is valid glTF
    if channels.is_empty() {
        let mut rot_floats = Vec::with_capacity(n_samples * 4);
        for _ in 0..n_samples {
            rot_floats.extend_from_slice(&[0.0, 0.0, 0.0, 1.0]);
        }
        let rot_acc = push_f32_slice(
            &mut bin_data,
            &mut buffer_views,
            &mut accessors,
            &rot_floats,
            "VEC4",
            n_samples,
            None,
        );
        samplers.push(json!({
            "input": time_acc,
            "interpolation": "LINEAR",
            "output": rot_acc
        }));
        channels.push(json!({
            "sampler": 0,
            "target": { "node": 0, "path": "rotation" }
        }));
    }

    while bin_data.len() % 4 != 0 {
        bin_data.push(0);
    }

    let gltf = json!({
        "asset": {
            "version": "2.0",
            "generator": "vrm-vrma-gen 0.1.0"
        },
        "extensionsUsed": ["VRMC_vrm_animation"],
        "extensions": {
            "VRMC_vrm_animation": {
                "specVersion": "1.0",
                "humanoid": {
                    "humanBones": human_bones_json
                }
            }
        },
        "scenes": [{ "nodes": [0] }],
        "scene": 0,
        "nodes": nodes_json,
        "buffers": [{ "byteLength": bin_data.len() }],
        "bufferViews": buffer_views,
        "accessors": accessors,
        "animations": [{
            "name": spec.name,
            "channels": channels,
            "samplers": samplers
        }]
    });

    let mut json_bytes = serde_json::to_vec(&gltf).unwrap();
    while json_bytes.len() % 4 != 0 {
        json_bytes.push(0x20); // space padding per glTF 2.0 spec
    }

    let total_len = 12 + 8 + json_bytes.len() + 8 + bin_data.len();
    let mut glb = Vec::with_capacity(total_len);
    glb.extend_from_slice(&0x4654_6C67u32.to_le_bytes()); // "glTF"
    glb.extend_from_slice(&2u32.to_le_bytes());
    glb.extend_from_slice(&(total_len as u32).to_le_bytes());
    // JSON chunk
    glb.extend_from_slice(&(json_bytes.len() as u32).to_le_bytes());
    glb.extend_from_slice(&0x4E4F_534Au32.to_le_bytes());
    glb.extend_from_slice(&json_bytes);
    // BIN chunk
    glb.extend_from_slice(&(bin_data.len() as u32).to_le_bytes());
    glb.extend_from_slice(&0x004E_4942u32.to_le_bytes());
    glb.extend_from_slice(&bin_data);
    glb
}

fn all_clips() -> Vec<ClipSpec> {
    vec![
        ClipSpec { name: "t_pose", duration: 1.0, samples: 2, eval: eval_t_pose },
        ClipSpec { name: "a_pose", duration: 1.0, samples: 2, eval: eval_a_pose },
        ClipSpec { name: "idle", duration: 3.0, samples: 61, eval: eval_idle },
        ClipSpec { name: "walk", duration: 1.0, samples: 41, eval: eval_walk },
        ClipSpec { name: "run", duration: 0.65, samples: 33, eval: eval_run },
        ClipSpec { name: "sit", duration: 2.5, samples: 41, eval: eval_sit },
        ClipSpec { name: "stretch_neck", duration: 4.0, samples: 65, eval: eval_stretch_neck },
        ClipSpec { name: "stretch_shoulder", duration: 4.0, samples: 65, eval: eval_stretch_shoulder },
        ClipSpec { name: "stretch_side", duration: 4.0, samples: 65, eval: eval_stretch_side },
        ClipSpec { name: "stretch_squat", duration: 3.0, samples: 61, eval: eval_stretch_squat },
        ClipSpec { name: "finger_test", duration: 3.5, samples: 71, eval: eval_finger_test },
        ClipSpec { name: "spring_bounce", duration: 2.0, samples: 61, eval: eval_spring_bounce },
    ]
}

fn main() -> anyhow::Result<()> {
    let out_dir = Path::new("assets/animations");
    fs::create_dir_all(out_dir)?;
    for spec in all_clips() {
        let bytes = build_vrma_glb(&spec);
        let path = out_dir.join(format!("{}.vrma", spec.name));
        fs::write(&path, &bytes)?;
        println!("Generated {} ({} bytes)", path.display(), bytes.len());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_generated_vrma_files_are_valid_glb_vrma() {
        for spec in all_clips() {
            let glb = build_vrma_glb(&spec);
            assert!(glb.len() > 20);
            assert_eq!(&glb[0..4], b"glTF");
            let version = u32::from_le_bytes(glb[4..8].try_into().unwrap());
            let total_len = u32::from_le_bytes(glb[8..12].try_into().unwrap()) as usize;
            assert_eq!(version, 2);
            assert_eq!(total_len, glb.len());

            let jlen = u32::from_le_bytes(glb[12..16].try_into().unwrap()) as usize;
            assert_eq!(&glb[16..20], b"JSON");
            let json_val: Value = serde_json::from_slice(&glb[20..20 + jlen]).unwrap();
            assert!(json_val["extensions"]["VRMC_vrm_animation"]["humanoid"]["humanBones"].is_object());
            let bin_offset = 20 + jlen;
            let blen = u32::from_le_bytes(glb[bin_offset..bin_offset + 4].try_into().unwrap()) as usize;
            assert_eq!(&glb[bin_offset + 4..bin_offset + 8], b"BIN\0");
            assert_eq!(bin_offset + 8 + blen, glb.len());

            // Validate every accessor bufferView byte range fits inside BIN
            let bvs = json_val["bufferViews"].as_array().unwrap();
            for acc in json_val["accessors"].as_array().unwrap() {
                let bv = &bvs[acc["bufferView"].as_u64().unwrap() as usize];
                let off = bv["byteOffset"].as_u64().unwrap() as usize;
                let len = bv["byteLength"].as_u64().unwrap() as usize;
                assert!(off + len <= blen, "Accessor exceeds BIN chunk in {}", spec.name);
            }
        }
    }
}
