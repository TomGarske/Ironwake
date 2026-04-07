## A single compartment aboard a ship. Holds crew, tracks fire/flood/damage, and
## connects to neighbors via an adjacency list for spread and pathing.
class_name ShipRoom
extends RefCounted

enum RoomType {
	HELM,
	GUN_DECK_PORT,
	GUN_DECK_STBD,
	RIGGING,
	CARPENTER,
	PUMPS,
	MAGAZINE,
	GALLEY_KITCHEN,
	CREW_QUARTERS,
	BRIG_JAIL,
	SICKBAY,
	OFFICERS_QUARTERS,
}

const ROOM_NAMES: Dictionary = {
	RoomType.HELM: "Helm",
	RoomType.GUN_DECK_PORT: "Guns Port",
	RoomType.GUN_DECK_STBD: "Guns Stbd",
	RoomType.RIGGING: "Rigging",
	RoomType.CARPENTER: "Carpenter",
	RoomType.PUMPS: "Pumps",
	RoomType.MAGAZINE: "Magazine",
	RoomType.GALLEY_KITCHEN: "Galley",
	RoomType.CREW_QUARTERS: "Quarters",
	RoomType.BRIG_JAIL: "Brig",
	RoomType.SICKBAY: "Sickbay",
	RoomType.OFFICERS_QUARTERS: "Officers",
}

## Which deck level the room sits on (drives flood propagation priority).
enum DeckLevel { UPPER, MAIN, LOWER }

# ── identity ──
var type: RoomType
var display_name: String
var deck_level: DeckLevel = DeckLevel.MAIN
## Unique index within the ship layout (0-based).
var room_index: int = 0

# ── crew ──
var max_crew: int = 4
var crew_count: int = 0

# ── system ──
## Upgrade tier (0 = base). Affects efficiency ceiling for this room's function.
var system_level: int = 0

# ── damage / hazard ──
## Structural damage to this room (0 = pristine, 1 = wrecked).
var damage: float = 0.0
## Fire intensity in this room (0 = clear, 1 = fully ablaze).
var fire_intensity: float = 0.0
## Whether the room is flooded (binary per-room; flood_level is ship-wide).
var flooded: bool = false

# ── graph ──
## Rooms reachable in one step (set by ShipLayout builder).
var adjacent_rooms: Array[ShipRoom] = []
## Schematic position for HUD rendering (normalized 0-1 range).
var position_on_hull: Vector2 = Vector2.ZERO


func _init(p_type: RoomType, p_max_crew: int = 4, p_deck: DeckLevel = DeckLevel.MAIN) -> void:
	type = p_type
	display_name = ROOM_NAMES.get(p_type, "Unknown")
	max_crew = p_max_crew
	deck_level = p_deck


func reset() -> void:
	crew_count = 0
	damage = 0.0
	fire_intensity = 0.0
	flooded = false


## Room efficiency: 0 when wrecked or unmanned, scales with damage.
func get_efficiency() -> float:
	if crew_count <= 0:
		return 0.0
	var staff_ratio: float = float(crew_count) / float(maxi(1, max_crew))
	var staff_eff: float
	if staff_ratio <= 1.0:
		staff_eff = 1.0 - (1.0 - staff_ratio) * (1.0 - staff_ratio)
	else:
		staff_eff = 1.0 + 0.15 * (1.0 - exp(-(staff_ratio - 1.0)))
	var dmg_eff: float = 1.0 - damage * 0.8
	return maxf(0.0, staff_eff * dmg_eff)


## Whether this room is on fire.
func is_burning() -> bool:
	return fire_intensity > 0.02


## BFS shortest-path distance (hop count) to another room. -1 if unreachable.
static func bfs_distance(from: ShipRoom, to: ShipRoom) -> int:
	if from == to:
		return 0
	var visited: Dictionary = {}
	var queue: Array[Array] = [[from, 0]]
	visited[from.room_index] = true
	while not queue.is_empty():
		var entry: Array = queue.pop_front()
		var current: ShipRoom = entry[0]
		var dist: int = int(entry[1])
		for neighbor: ShipRoom in current.adjacent_rooms:
			if neighbor == to:
				return dist + 1
			if not visited.has(neighbor.room_index):
				visited[neighbor.room_index] = true
				queue.append([neighbor, dist + 1])
	return -1
