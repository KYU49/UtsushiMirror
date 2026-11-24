use std::net::{SocketAddr, ToSocketAddrs, UdpSocket};
use std::time::Instant;
use vrm_protocol::{encode_vmc_bundles, VmcFrame};

pub struct OscSenderHandle {
    socket: UdpSocket,
    target: SocketAddr,
    target_display: String,
    t0: Instant,
    packets_sent: u64,
    frames_sent: u64,
    last_error: String,
}

impl OscSenderHandle {
    pub fn start(host: &str, port: u16) -> Result<Self, String> {
        let h = host.trim();
        let host_clean = if h.is_empty() { "127.0.0.1" } else { h };
        let addrs: Vec<SocketAddr> = (host_clean, port)
            .to_socket_addrs()
            .map_err(|e| format!("resolve VMC target '{host_clean}:{port}': {e}"))?
            .collect();
        let target = addrs
            .iter()
            .copied()
            .find(|a| a.is_ipv4())
            .or_else(|| addrs.first().copied())
            .ok_or_else(|| format!("unable to resolve VMC target '{host_clean}:{port}'"))?;

        let bind_local: SocketAddr = if target.is_ipv6() {
            ([0u16; 8], 0).into()
        } else {
            ([0u8, 0, 0, 0], 0).into()
        };
        let socket = UdpSocket::bind(bind_local).map_err(|e| format!("bind UDP sender: {e}"))?;
        let _ = socket.set_nonblocking(true);

        Ok(Self {
            socket,
            target,
            target_display: format!("{host_clean}:{port}"),
            t0: Instant::now(),
            packets_sent: 0,
            frames_sent: 0,
            last_error: String::new(),
        })
    }

    pub fn send_frame_json(&mut self, frame_json: &str) -> Result<usize, String> {
        let frame: VmcFrame =
            serde_json::from_str(frame_json).map_err(|e| format!("invalid VmcFrame JSON: {e}"))?;
        let time_sec = self.t0.elapsed().as_secs_f32();
        let bundles = encode_vmc_bundles(&frame, time_sec, 12)
            .map_err(|e| format!("encode VMC bundle: {e}"))?;
        let mut sent = 0usize;
        for pkt in &bundles {
            match self.socket.send_to(pkt, self.target) {
                Ok(_) => {
                    sent += 1;
                    self.packets_sent = self.packets_sent.saturating_add(1);
                }
                Err(e) => {
                    let msg = format!("UDP send_to {}: {e}", self.target);
                    self.last_error = msg.clone();
                    return Err(msg);
                }
            }
        }
        self.frames_sent = self.frames_sent.saturating_add(1);
        self.last_error.clear();
        Ok(sent)
    }

    pub fn status_json(&self) -> String {
        serde_json::json!({
            "running": true,
            "target": self.target_display,
            "resolved": self.target.to_string(),
            "packets_sent": self.packets_sent,
            "frames_sent": self.frames_sent,
            "last_error": self.last_error,
        })
        .to_string()
    }
}
