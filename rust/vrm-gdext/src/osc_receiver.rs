use std::net::{SocketAddr, UdpSocket};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::Duration;
use vrm_protocol::{apply_vmc_events, decode_osc_packet, VmcFrame};

pub struct OscReceiverHandle {
    stop_flag: Arc<AtomicBool>,
    frame: Arc<Mutex<VmcFrame>>,
    thread: Option<JoinHandle<()>>,
}

impl OscReceiverHandle {
    pub fn start(port: u16) -> Result<Self, String> {
        let addr: SocketAddr = ([127, 0, 0, 1], port).into();
        let socket = UdpSocket::bind(addr).map_err(|e| format!("bind UDP {addr}: {e}"))?;
        socket
            .set_read_timeout(Some(Duration::from_millis(50)))
            .map_err(|e| format!("set_read_timeout: {e}"))?;

        let stop_flag = Arc::new(AtomicBool::new(false));
        let stop_clone = Arc::clone(&stop_flag);
        let frame = Arc::new(Mutex::new(VmcFrame::default()));
        let frame_clone = Arc::clone(&frame);

        let thread = std::thread::Builder::new()
            .name("vrm-osc-receiver".into())
            .spawn(move || {
                let mut buf = [0u8; 65536];
                while !stop_clone.load(Ordering::Relaxed) {
                    match socket.recv_from(&mut buf) {
                        Ok((len, _)) => {
                            if let Ok(events) = decode_osc_packet(&buf[..len]) {
                                if !events.is_empty() {
                                    if let Ok(mut guard) = frame_clone.lock() {
                                        apply_vmc_events(&mut guard, &events);
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
            frame,
            thread: Some(thread),
        })
    }

    pub fn take_if_newer(&self, last_seq: u64) -> Option<(u64, String)> {
        let mut guard = self.frame.lock().ok()?;
        if guard.seq == last_seq {
            return None;
        }
        let seq = guard.seq;
        let json = serde_json::to_string(&*guard).ok()?;
        guard.blend_apply = false;
        Some((seq, json))
    }

    pub fn stop(mut self) {
        self.stop_flag.store(true, Ordering::Relaxed);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}
