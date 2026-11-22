use futures_util::{SinkExt, StreamExt};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use tokio::net::TcpListener;
use tokio::sync::{mpsc, watch};
use tokio_tungstenite::tungstenite::handshake::server::{ErrorResponse, Request, Response};
use tokio_tungstenite::tungstenite::http::StatusCode;
use tokio_tungstenite::tungstenite::Message;
use vrm_protocol::{QueuedRpcRequest, RpcError, RpcRequest, RpcResponse};

type ClientMap = Arc<Mutex<HashMap<u64, mpsc::Sender<String>>>>;

pub struct WsServerHandle {
    shutdown_tx: watch::Sender<bool>,
    clients: ClientMap,
    port: u16,
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
        let bound_port = std_listener.local_addr().map(|a| a.port()).unwrap_or(port);
        std_listener
            .set_nonblocking(true)
            .map_err(|e| format!("set_nonblocking: {e}"))?;

        let (shutdown_tx, shutdown_rx) = watch::channel(false);
        let (ready_tx, ready_rx) = std::sync::mpsc::sync_channel::<Result<(), String>>(1);
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
                        let _ = ready_tx.send(Err(format!("Failed to build tokio runtime: {e}")));
                        return;
                    }
                };
                rt.block_on(async move {
                    let listener = match TcpListener::from_std(std_listener) {
                        Ok(l) => l,
                        Err(e) => {
                            let _ = ready_tx.send(Err(format!("Failed to convert TcpListener: {e}")));
                            return;
                        }
                    };
                    let _ = ready_tx.send(Ok(()));
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
                                            let Ok(ws_stream) = tokio_tungstenite::accept_hdr_async(
                                                stream,
                                                |req: &Request, res: Response| -> Result<Response, ErrorResponse> {
                                                    if req
                                                        .headers()
                                                        .get("origin")
                                                        .is_some_and(|v| !v.as_bytes().is_empty())
                                                    {
                                                        let mut err_res = ErrorResponse::new(Some(
                                                            "Forbidden origin".to_string(),
                                                        ));
                                                        *err_res.status_mut() = StatusCode::FORBIDDEN;
                                                        return Err(err_res);
                                                    }
                                                    Ok(res)
                                                },
                                            )
                                            .await
                                            else {
                                                return;
                                            };
                                            let (mut write, mut read) = ws_stream.split();
                                            let (out_tx, mut out_rx) = mpsc::channel::<String>(256);
                                            if let Ok(mut guard) = clients_inner.lock() {
                                                guard.insert(client_id, out_tx.clone());
                                            }

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
                                                                            let _ = out_tx.try_send(json);
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
                                            if let Ok(mut guard) = clients_inner.lock() {
                                                guard.remove(&client_id);
                                            }
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

        match ready_rx.recv() {
            Ok(Ok(())) => {}
            Ok(Err(e)) => return Err(e),
            Err(_) => return Err("ws server thread exited before ready".to_string()),
        }

        Ok(Self {
            shutdown_tx,
            clients,
            port: bound_port,
            thread: Some(thread),
        })
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn send_to_client(&self, client_id: u64, message: String) {
        if let Ok(guard) = self.clients.lock() {
            if let Some(tx) = guard.get(&client_id) {
                let _ = tx.try_send(message);
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;
    use tokio_tungstenite::tungstenite::client::IntoClientRequest;
    use tokio_tungstenite::tungstenite::http::HeaderValue;

    #[test]
    fn allows_local_client_without_origin_and_routes_rpc() {
        let (rpc_tx, rpc_rx) = crossbeam_channel::unbounded();
        let server = WsServerHandle::start(0, rpc_tx).expect("start ws server");
        let url = format!("ws://127.0.0.1:{}", server.port());

        let (mut sock, _) = tokio_tungstenite::tungstenite::connect(&url).expect("connect local");
        sock.send(Message::Text(
            r#"{"jsonrpc":"2.0","id":1,"method":"ping","params":{}}"#.into(),
        ))
        .expect("send ping");

        let req = rpc_rx
            .recv_timeout(Duration::from_secs(2))
            .expect("receive queued rpc");
        assert_eq!(req.method, "ping");

        let resp = RpcResponse::ok(req.id, serde_json::json!({ "pong": true }));
        server.send_to_client(
            req.client_id,
            serde_json::to_string(&resp).expect("serialize resp"),
        );

        let reply = sock.read().expect("read ws reply");
        match reply {
            Message::Text(txt) => {
                let parsed: RpcResponse = serde_json::from_str(&txt).expect("parse resp");
                assert_eq!(parsed.result.unwrap()["pong"], true);
            }
            other => panic!("unexpected ws message: {other:?}"),
        }
        let _ = sock.close(None);
        server.stop();
    }

    #[test]
    fn rejects_browser_origin_header_cswsh() {
        let (rpc_tx, _rpc_rx) = crossbeam_channel::unbounded();
        let server = WsServerHandle::start(0, rpc_tx).expect("start ws server");
        let url = format!("ws://127.0.0.1:{}", server.port());

        let mut req = url.into_client_request().expect("build request");
        req.headers_mut().insert(
            "Origin",
            HeaderValue::from_static("https://evil.example"),
        );

        let res = tokio_tungstenite::tungstenite::connect(req);
        match res {
            Err(tokio_tungstenite::tungstenite::Error::Http(resp)) => {
                assert_eq!(resp.status(), StatusCode::FORBIDDEN);
            }
            Err(other) => panic!("expected HTTP 403 rejection, got error: {other:?}"),
            Ok(_) => panic!("expected Origin connection to be rejected"),
        }
        server.stop();
    }
}
