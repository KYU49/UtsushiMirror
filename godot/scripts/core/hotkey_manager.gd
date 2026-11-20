class_name HotkeyManager
extends Node

## Manages F1-F12 expression/action shortcuts and global hotkeys (via VrmBridge on Windows).

signal hotkey_triggered(action: String)

var global_enabled: bool = false
var bindings: Dictionary = {
	"F1": "expr:neutral",
	"F2": "expr:happy",
	"F3": "expr:angry",
	"F4": "expr:sad",
	"F5": "expr:relaxed",
	"F6": "expr:surprised",
	"F7": "expr:aa",
	"F8": "expr:ih",
	"F9": "expr:ou",
	"F10": "expr:blink",
	"F11": "action:screenshot",
	"F12": "action:toggle_record",
	"Ctrl+Shift+S": "action:toggle_settings",
}

var _bridge: Node = null


func setup(p_bridge: Node) -> void:
	_bridge = p_bridge
	_sync_global()


func apply_params(params: Dictionary) -> void:
	if params.has("global_enabled") and params["global_enabled"] != null:
		global_enabled = bool(params["global_enabled"])
	if params.has("bindings") and typeof(params["bindings"]) == TYPE_DICTIONARY:
		for k in params["bindings"].keys():
			# クリックスルー解除のホットキーは廃止 (クリックスルー中は効かないため)。タスクトレイから解除する
			if str(params["bindings"][k]) == "action:toggle_click_through":
				bindings.erase(str(k))
				continue
			bindings[str(k)] = str(params["bindings"][k])
	_sync_global()


func to_dict() -> Dictionary:
	return {
		"global_enabled": global_enabled,
		"bindings": bindings.duplicate(),
	}


func poll_global() -> void:
	if not global_enabled or _bridge == null or not _bridge.has_method("poll_global_hotkeys"):
		return
	var triggered: PackedStringArray = _bridge.poll_global_hotkeys()
	for action in triggered:
		hotkey_triggered.emit(action)


func handle_key_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var ek := event as InputEventKey
	if not ek.pressed or ek.echo:
		return false
	var combo := _event_to_combo(ek)
	if combo != "" and bindings.has(combo):
		hotkey_triggered.emit(str(bindings[combo]))
		return true
	return false


func _sync_global() -> void:
	if _bridge != null and _bridge.has_method("configure_global_hotkeys"):
		_bridge.configure_global_hotkeys(global_enabled, JSON.stringify(bindings))


static func _event_to_combo(ek: InputEventKey) -> String:
	var parts := PackedStringArray()
	if ek.ctrl_pressed:
		parts.append("Ctrl")
	if ek.shift_pressed:
		parts.append("Shift")
	if ek.alt_pressed:
		parts.append("Alt")
	var k := OS.get_keycode_string(ek.keycode)
	if k == "":
		return ""
	parts.append(k)
	return "+".join(parts)
