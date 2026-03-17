extends Node

## Central registry of terrain types.
## Built-in terrains live in TERRAIN_TYPES; user-created terrains are in custom_terrains.
## Emits terrain_updated whenever the registry changes (strategy_game listens to repaint).

signal terrain_updated

var TERRAIN_TYPES: Dictionary = {
	"deep_ocean": {
		"label": "Deep Ocean",
		"color": Color("#0D1A66"),
		"required_movement_types": ["deep_ocean_underwater"],
	},
	"shallow_ocean": {
		"label": "Shallow Ocean",
		"color": Color("#2666CC"),
		"required_movement_types": ["water", "deep_ocean_underwater", "air"],
	},
	"surface_water": {
		"label": "Coast / Surface Water",
		"color": Color("#4DB3E6"),
		"required_movement_types": ["water", "deep_ocean_underwater", "land", "air"],
	},
	"land": {
		"label": "Land",
		"color": Color("#4D9933"),
		"required_movement_types": ["land", "air"],
	},
	"mountain": {
		"label": "Mountain",
		"color": Color("#999999"),
		"required_movement_types": ["air"],
	},
}

# Each entry: { id: String, label: String, color: Color, required_movement_types: Array[String] }
var custom_terrains: Array[Dictionary] = []


func _ready() -> void:
	# Restore any custom terrains persisted via GameState (future save/load hook)
	if GameState.custom_terrains.size() > 0:
		custom_terrains = GameState.custom_terrains.duplicate(true)


func get_all_terrain_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: String in TERRAIN_TYPES.keys():
		ids.append(k)
	for ct: Dictionary in custom_terrains:
		ids.append(ct["id"])
	return ids


func get_terrain_label(id: String) -> String:
	if TERRAIN_TYPES.has(id):
		return TERRAIN_TYPES[id]["label"]
	for ct: Dictionary in custom_terrains:
		if ct["id"] == id:
			return ct["label"]
	return id


func get_required_movement_types(id: String) -> Array[String]:
	var result: Array[String] = []
	if TERRAIN_TYPES.has(id):
		result.assign(TERRAIN_TYPES[id]["required_movement_types"])
		return result
	for ct: Dictionary in custom_terrains:
		if ct["id"] == id:
			result.assign(ct["required_movement_types"])
			return result
	return result


func get_terrain_color(id: String) -> Color:
	if TERRAIN_TYPES.has(id):
		return TERRAIN_TYPES[id]["color"]
	for ct: Dictionary in custom_terrains:
		if ct["id"] == id:
			return ct["color"]
	return Color.WHITE


func is_builtin(id: String) -> bool:
	return TERRAIN_TYPES.has(id)


func is_id_unique(id: String) -> bool:
	if TERRAIN_TYPES.has(id):
		return false
	for ct: Dictionary in custom_terrains:
		if ct["id"] == id:
			return false
	return true


func add_custom_terrain(entry: Dictionary) -> void:
	custom_terrains.append(entry)
	GameState.custom_terrains = custom_terrains.duplicate(true)
	GameState.save()
	terrain_updated.emit()


func update_custom_terrain(id: String, updated: Dictionary) -> void:
	for i in custom_terrains.size():
		if custom_terrains[i]["id"] == id:
			custom_terrains[i] = updated
			GameState.custom_terrains = custom_terrains.duplicate(true)
			GameState.save()
			terrain_updated.emit()
			return


func remove_custom_terrain(id: String) -> void:
	custom_terrains = custom_terrains.filter(func(ct: Dictionary) -> bool: return ct["id"] != id)
	GameState.custom_terrains = custom_terrains.duplicate(true)
	GameState.save()
	terrain_updated.emit()


## Updates any terrain type (built-in or custom). Built-in changes are session-only.
func update_terrain(id: String, updated: Dictionary) -> void:
	if TERRAIN_TYPES.has(id):
		TERRAIN_TYPES[id]["label"] = updated.get("label", TERRAIN_TYPES[id]["label"])
		TERRAIN_TYPES[id]["required_movement_types"] = updated.get("required_movement_types", [])
		terrain_updated.emit()
	else:
		update_custom_terrain(id, updated)


## Removes any terrain type (built-in or custom).
func remove_terrain(id: String) -> void:
	if TERRAIN_TYPES.has(id):
		TERRAIN_TYPES.erase(id)
		terrain_updated.emit()
	else:
		remove_custom_terrain(id)
