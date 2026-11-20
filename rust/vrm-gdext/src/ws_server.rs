use futures_util::{SinkExt, StreamExt};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use tokio::net::TcpListener;
use tokio::sync::{mpsc, watch};
use tokio_tungstenite::tungstenite::Message;
use vrm_protocol::{QueuedRpcRequest, RpcError, RpcRequest, RpcResponse};

type ClientMap = Arc<Mutex<HashMap<u64, mpsc::UnboundedSender<String>>>>;

pub struct WsServerHandle {
    shutdown_tx: watch::Sender<bool>,
    clients: ClientMap,
    thread: Option<JoinHandle<()>>,
}

impl WsServerHandle {
    pub fn start(
        port: u16,
        rpc_tx: crossbeam_channel::Sender<QueuedRpcRequest>,
    ) -> Result<Self, String> {
        let addr: SocketAddr = ([127, 0, 0, 1], port).into();
        let std_listener =
            std::net::TcpListener::bind(addr).map_err(|e| format!("bind {addr}: {e}"))?;
        std_listener
            .set_nonblocking(true)
            .map_err(|e| format!("set_nonblocking: {e}"))?;

        let (shutdown_tx, shutdown_rx) = watch::channel(false);
        let clients: ClientMap = Arc::new(Mutex::new(HashMap::new()));
        let clients_clone = Arc::clone(&clients);

        let thread = std::thread::Builder::new()
            .name("vrm-ws-server".into())
            .spawn(move || {
                let rt = match tokio::runtime::Builder::new_multi_thread()
                    .worker_threads(2)
                    .enable_all()
                    .build()
                {
                    Ok(rt) => rt,
                    Err(e) => {
                        eprintln!("Failed to build tokio runtime: {e}");
                        return;
                    }
                };
                rt.block_on(async move {
                    let listener = match TcpListener::from_std(std_listener) {
                        Ok(l) => l,
                        Err(e) => {
                            eprintln!("Failed to convert TcpListener: {e}");
                            return;
                        }
                    };
                    let next_id = AtomicU64::new(1);
                    let mut shutdown_rx = shutdown_rx;
                    loop {
                        tokio::select! {
                            _ = shutdown_rx.changed() => {
                                if *shutdown_rx.borrow() {
                                    break;
                                }
                            }
                            accepted = listener.accept() => {
                                match accepted {
                                    Ok((stream, _peer)) => {
                                        let client_id = next_id.fetch_add(1, Ordering::Relaxed);
                                        let clients_inner = Arc::clone(&clients_clone);
                                        let rpc_tx_inner = rpc_tx.clone();
                                        let mut client_shutdown = shutdown_rx.clone();
                                        tokio::spawn(async move {
                                            let Ok(ws_stream) = tokio_tungstenite::accept_async(stream).await else {
                                                return;
                                            };
                                            let (mut write, mut read) = ws_stream.split();
                                            let (out_tx, mut out_rx) = mpsc::unbounded_channel::<String>();
                                            clients_inner.lock().unwrap().insert(client_id, out_tx.clone());

                                            loop {
                                                tokio::select! {
                                                    _ = client_shutdown.changed() => {
                                                        if *client_shutdown.borrow() {
                                                            break;
                                                        }
                                                    }
                                                    Some(msg_out) = out_rx.recv() => {
                                                        if write.send(Message::Text(msg_out.into())).await.is_err() {
                                                            break;
                                                        }
                                                    }
                                                    incoming = read.next() => {
                                                        match incoming {
                                                            Some(Ok(Message::Text(text))) => {
                                                                match serde_json::from_str::<RpcRequest>(&text) {
                                                                    Ok(req) => {
                                                                        let queued = QueuedRpcRequest {
                                                                            client_id,
                                                                            id: req.id,
                                                                            method: req.method,
                                                                            params: req.params,
                                                                        };
                                                                        let _ = rpc_tx_inner.send(queued);
                                                                    }
                                                                    Err(e) => {
                                                                        let err = RpcResponse::err(
                                                                            serde_json::Value::Null,
                                                                            RpcError::invalid_params(format!("Invalid JSON-RPC request: {e}")),
                                                                        );
                                                                        if let Ok(json) = serde_json::to_string(&err) {
                                                                            let _ = out_tx.send(json);
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                            Some(Ok(Message::Ping(payload))) => {
                                                                let _ = write.send(Message::Pong(payload)).await;
                                                            }
                                                            Some(Ok(Message::Close(_))) | None | Some(Err(_)) => break,
                                                            _ => {}
                                                        }
                                                    }
                                                }
                                            }
                                            clients_inner.lock().unwrap().remove(&client_id);
                                        });
                                    }
                                    Err(_) => break,
                                }
                            }
                        }
                    }
                });
            })
            .map_err(|e| format!("spawn thread: {e}"))?;

        Ok(Self {
            shutdown_tx,
            clients,
            thread: Some(thread),
        })
    }

    pub fn send_to_client(&self, client_id: u64, message: String) {
        if let Ok(guard) = self.clients.lock() {
            if let Some(tx) = guard.get(&client_id) {
                let _ = tx.send(message);
            }
        }
    }

    pub fn stop(mut self) {
        let _ = self.shutdown_tx.send(true);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}
