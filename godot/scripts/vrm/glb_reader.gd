class_name GlbReader
extends RefCounted

## Reads GLB JSON and BIN chunks via VrmBridge (native Rust) or pure GDScript fallback.

static func read_glb(path: String, bridge: Node = null) -> Dictionary:
	if bridge != null and bridge.has_method("read_glb_chunks"):
		var res: Dictionary = bridge.read_glb_chunks(path)
		if res.get("ok", false):
			var parsed = JSON.parse_string(str(res.get("json", "")))
			if typeof(parsed) == TYPE_DICTIONARY:
				return {
					"ok": true,
					"json": parsed,
					"bin": res.get("bin", PackedByteArray()),
				}
			return {"ok": false, "error": "Failed to parse GLB JSON chunk"}
		return res

	# Pure GDScript fallback (works without GDExtension too)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Failed to open file: " + path}
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 12:
		return {"ok": false, "error": "File too small to be GLB"}

	var magic := bytes.decode_u32(0)
	var version := bytes.decode_u32(4)
	var total_len := bytes.decode_u32(8)
	if magic != 0x46546C67:
		return {"ok": false, "error": "Invalid GLB magic"}
	if version != 2:
		return {"ok": false, "error": "Unsupported GLB version: " + str(version)}

	var end := mini(int(total_len), bytes.size())
	var offset := 12
	var json_dict: Variant = null
	var bin_chunk := PackedByteArray()
	while offset + 8 <= end:
		var chunk_len := int(bytes.decode_u32(offset))
		var chunk_type := bytes.decode_u32(offset + 4)
		offset += 8
		if offset + chunk_len > end:
			return {"ok": false, "error": "GLB chunk exceeds file length"}
		var slice := bytes.slice(offset, offset + chunk_len)
		if chunk_type == 0x4E4F534A:
			json_dict = JSON.parse_string(slice.get_string_from_utf8())
		elif chunk_type == 0x004E4942:
			bin_chunk = slice
		offset += chunk_len

	if typeof(json_dict) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Missing or invalid JSON chunk"}
	return {"ok": true, "json": json_dict, "bin": bin_chunk}


static func detect_vrm_version(gltf_json: Dictionary) -> String:
	var exts: Dictionary = gltf_json.get("extensions", {})
	if exts.has("VRMC_vrm"):
		return "1.0"
	if exts.has("VRM"):
		return "0.x"
	return "gltf"
