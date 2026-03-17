extends Node

## Minimal persistence layer. Saves/loads custom terrain definitions to disk.

const SAVE_PATH := "user://custom_terrains.json"

var custom_terrains: Array[Dictionary] = []


func _ready() -> void:
	_load_from_disk()


func save() -> void:
	var serialized: Array = []
	for ct: Dictionary in custom_terrains:
		var entry := ct.duplicate()
		var c: Color = entry.get("color", Color.WHITE)
		entry["color"] = [c.r, c.g, c.b, c.a]
		serialized.append(entry)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(serialized, "\t"))
	else:
		push_warning("GameState: could not write to %s" % SAVE_PATH)


func _load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return
	custom_terrains.clear()
	for entry: Variant in parsed:
		if not entry is Dictionary:
			continue
		if entry.has("color") and entry["color"] is Array:
			var c: Array = entry["color"]
			entry["color"] = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3])) if c.size() >= 4 else Color.WHITE
		custom_terrains.append(entry)
