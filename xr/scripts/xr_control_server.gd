extends Node

## 外部プログラムから XR 内のキャラクターを動かすための受信口 (純 GDScript)。
##
## 1. WebSocket JSON-RPC 2.0 (既定 :19100) — デスクトップ版と同じメソッド名の一部
##    (play_animation / set_expressions / set_bones / set_lookat ...) と、XR 専用の
##    set_avatar_transform / place_in_front などを受け付ける。
## 2. VMC Protocol (OSC over UDP, 既定 :39539) — PC の Webカメラトラッカーや
##    他の VMC 対応ソフトから、ボーン回転と表情をリアルタイムに受け取る。

signal rpc_request(peer_id: int, id, method: String, params: Dictionary)

var ws_port: int = 19100
var vmc_port: int = 39539

var _tcp := TCPServer.new()
var _peers: Dictionary = {}  # id -> WebSocketPeer
var _next_peer_id: int = 1
var _udp := PacketPeerUDP.new()

# VMC で受け取った最新の値 (呼び出し側が毎フレーム取り出す)
var vmc_bones: Dictionary = {}       # vrm ボーン名 -> Quaternion (VRM/Godot 座標)
var vmc_blends: Dictionary = {}      # 表情名 -> float
var vmc_blend_dirty: bool = false
var vmc_root_pos = null              # Vector3 or null
var vmc_last_msec: int = 0


func start() -> Dictionary:
	var r := {"ws": _tcp.listen(ws_port) == OK, "vmc": _udp.bind(vmc_port) == OK}
	return r


func stop() -> void:
	for p in _peers.values():
		p.close()
	_peers.clear()
	_tcp.stop()
	_udp.close()


func client_count() -> int:
	return _peers.size()


func _process(_delta: float) -> void:
	_poll_ws()
	_poll_vmc()


# ---------------------------------------------------------------------------
# WebSocket JSON-RPC
# ---------------------------------------------------------------------------
func _poll_ws() -> void:
	while _tcp.is_listening() and _tcp.is_connection_available():
		var conn := _tcp.take_connection()
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 22
		if ws.accept_stream(conn) == OK:
			_peers[_next_peer_id] = ws
			_next_peer_id += 1
	var closed: Array = []
	for pid in _peers.keys():
		var ws: WebSocketPeer = _peers[pid]
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			closed.append(pid)
			continue
		if st != WebSocketPeer.STATE_OPEN:
			continue
		while ws.get_available_packet_count() > 0:
			var txt := ws.get_packet().get_string_from_utf8()
			var req = JSON.parse_string(txt)
			if typeof(req) != TYPE_DICTIONARY:
				send_error(pid, null, -32700, "Parse error")
				continue
			var params = req.get("params", {})
			if typeof(params) != TYPE_DICTIONARY:
				params = {}
			rpc_request.emit(pid, req.get("id", null), str(req.get("method", "")), params)
	for pid in closed:
		_peers.erase(pid)


func send_result(peer_id: int, id, result) -> void:
	_send(peer_id, {"jsonrpc": "2.0", "id": id, "result": result})


func send_error(peer_id: int, id, code: int, msg: String) -> void:
	_send(peer_id, {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": msg}})


func _send(peer_id: int, d: Dictionary) -> void:
	if d.get("id", null) == null and not d.has("error"):
		return  # 通知 (id なし) には返事しない
	# JSON の数値は float になるので、整数の id は整数で返す
	var rid = d.get("id", null)
	if typeof(rid) == TYPE_FLOAT and rid == floorf(rid):
		d["id"] = int(rid)
	var ws: WebSocketPeer = _peers.get(peer_id, null)
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))


# ---------------------------------------------------------------------------
# VMC (OSC) 受信
# ---------------------------------------------------------------------------
func _poll_vmc() -> void:
	var n := 0
	while _udp.get_available_packet_count() > 0 and n < 256:
		n += 1
		var pkt := _udp.get_packet()
		_parse_packet(pkt)
		vmc_last_msec = Time.get_ticks_msec()


func _parse_packet(b: PackedByteArray) -> void:
	if b.size() >= 16 and b.slice(0, 8).get_string_from_ascii() == "#bundle":
		var off := 16
		while off + 4 <= b.size():
			var sz := _be_i32(b, off)
			off += 4
			if sz <= 0 or off + sz > b.size():
				return
			_parse_packet(b.slice(off, off + sz))
			off += sz
	else:
		_parse_message(b)


func _parse_message(b: PackedByteArray) -> void:
	var r := _read_str(b, 0)
	var addr: String = r[0]
	var off: int = r[1]
	if off >= b.size():
		return
	var t := _read_str(b, off)
	var tags: String = t[0]
	off = t[1]
	var args: Array = []
	for i in range(1, tags.length()):
		var c := tags[i]
		if c == "f":
			args.append(_be_f32(b, off)); off += 4
		elif c == "i":
			args.append(_be_i32(b, off)); off += 4
		elif c == "s":
			var s := _read_str(b, off)
			args.append(s[0]); off = s[1]
		else:
			return
		if off > b.size():
			return
	match addr:
		"/VMC/Ext/Bone/Pos":
			if args.size() >= 8:
				# Unity 座標 → VRM/Godot 座標
				var q := Quaternion(float(args[4]), -float(args[5]), -float(args[6]), float(args[7])).normalized()
				vmc_bones[_unity_bone_to_vrm(str(args[0]))] = q
		"/VMC/Ext/Root/Pos":
			if args.size() >= 4:
				vmc_root_pos = Vector3(-float(args[1]), float(args[2]), float(args[3]))
		"/VMC/Ext/Blend/Val":
			if args.size() >= 2:
				vmc_blends[str(args[0])] = float(args[1])
		"/VMC/Ext/Blend/Apply":
			vmc_blend_dirty = true


static func _unity_bone_to_vrm(raw: String) -> String:
	if raw.is_empty():
		return raw
	var n := raw.substr(0, 1).to_lower() + raw.substr(1)
	if n.ends_with("ThumbProximal"):
		return n.trim_suffix("ThumbProximal") + "ThumbMetacarpal"
	if n.ends_with("ThumbIntermediate"):
		return n.trim_suffix("ThumbIntermediate") + "ThumbProximal"
	return n


static func _read_str(b: PackedByteArray, off: int) -> Array:
	var end := off
	while end < b.size() and b[end] != 0:
		end += 1
	var s := b.slice(off, end).get_string_from_utf8()
	var next := end + 1
	next = (next + 3) & ~3
	return [s, next]


static func _be_i32(b: PackedByteArray, off: int) -> int:
	if off + 4 > b.size():
		return 0
	var s := b.slice(off, off + 4)
	s.reverse()
	return s.decode_s32(0)


static func _be_f32(b: PackedByteArray, off: int) -> float:
	if off + 4 > b.size():
		return 0.0
	var s := b.slice(off, off + 4)
	s.reverse()
	return s.decode_float(0)
