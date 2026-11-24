use std::collections::VecDeque;
use std::net::{IpAddr, SocketAddr, UdpSocket};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};
use vrm_protocol::{apply_vmc_events, decode_osc_packet, VmcFrame};

struct ReceiverState {
    frame: VmcFrame,
    bind_addr: String,
    port: u16,
    last_peer: String,
    packets_total: u64,
    recent_rx: VecDeque<Instant>,
    last_rx: Option<Instant>,
}

pub struct OscReceiverHandle {
    stop_flag: Arc<AtomicBool>,
    state: Arc<Mutex<ReceiverState>>,
    thread: Option<JoinHandle<()>>,
}

impl OscReceiverHandle {
    pub fn start(bind_host: &str, port: u16) -> Result<Self, String> {
        let ip: IpAddr = bind_host
            .trim()
            .parse()
            .map_err(|e| format!("invalid bind IP '{bind_host}': {e}"))?;
        let addr: SocketAddr = (ip, port).into();
        let socket = UdpSocket::bind(addr).map_err(|e| format!("bind UDP {addr}: {e}"))?;
        socket
            .set_read_timeout(Some(Duration::from_millis(50)))
            .map_err(|e| format!("set_read_timeout: {e}"))?;

        let stop_flag = Arc::new(AtomicBool::new(false));
        let stop_clone = Arc::clone(&stop_flag);
        let state = Arc::new(Mutex::new(ReceiverState {
            frame: VmcFrame::default(),
            bind_addr: ip.to_string(),
            port,
            last_peer: String::new(),
            packets_total: 0,
            recent_rx: VecDeque::with_capacity(128),
            last_rx: None,
        }));
        let state_clone = Arc::clone(&state);

        let thread = std::thread::Builder::new()
            .name("vrm-osc-receiver".into())
            .spawn(move || {
                let mut buf = [0u8; 65536];
                while !stop_clone.load(Ordering::Relaxed) {
                    match socket.recv_from(&mut buf) {
                        Ok((len, peer)) => {
                            if let Ok(events) = decode_osc_packet(&buf[..len]) {
                                if !events.is_empty() {
                                    if let Ok(mut guard) = state_clone.lock() {
                                        apply_vmc_events(&mut guard.frame, &events);
                                        let now = Instant::now();
                                        while let Some(&front) = guard.recent_rx.front() {
                                            if now.saturating_duration_since(front) > Duration::from_secs(1) {
                                                guard.recent_rx.pop_front();
                                            } else {
                                                break;
                                            }
                                        }
                                        guard.recent_rx.push_back(now);
                                        guard.packets_total = guard.packets_total.saturating_add(1);
                                        guard.last_rx = Some(now);
                                        guard.last_peer = peer.to_string();
                                    }
                                }
                            }
                        }
                        Err(e)
                            if e.kind() == std::io::ErrorKind::WouldBlock
                                || e.kind() == std::io::ErrorKind::TimedOut =>
                        {
                            continue;
                        }
                        Err(_) => break,
                    }
                }
            })
            .map_err(|e| format!("spawn osc thread: {e}"))?;

        Ok(Self {
            stop_flag,
            state,
            thread: Some(thread),
        })
    }

    pub fn take_if_newer(&self, last_seq: u64) -> Option<(u64, String)> {
        let mut guard = self.state.lock().ok()?;
        if guard.frame.seq == last_seq {
            return None;
        }
        let seq = guard.frame.seq;
        let json = serde_json::to_string(&guard.frame).ok()?;
        guard.frame.blend_apply = false;
        guard.frame.blend_dirty = false;
        Some((seq, json))
    }

    pub fn status_json(&self) -> String {
        let Ok(mut guard) = self.state.lock() else {
            return r#"{"running":false,"active":false}"#.to_string();
        };
        let now = Instant::now();
        while let Some(&front) = guard.recent_rx.front() {
            if now.saturating_duration_since(front) > Duration::from_secs(1) {
                guard.recent_rx.pop_front();
            } else {
                break;
            }
        }
        let active = guard
            .last_rx
            .map(|t| now.saturating_duration_since(t) < Duration::from_millis(1500))
            .unwrap_or(false);
        serde_json::json!({
            "running": true,
            "bind": guard.bind_addr,
            "port": guard.port,
            "last_peer": guard.last_peer,
            "packets_per_sec": guard.recent_rx.len() as u32,
            "packets_total": guard.packets_total,
            "active": active,
        })
        .to_string()
    }

    pub fn stop(mut self) {
        self.stop_flag.store(true, Ordering::Relaxed);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}
