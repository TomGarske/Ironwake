## Factory: builds a room graph (Array[ShipRoom]) for each ship class.
## Adjacency drives fire spread, crew pathing, and flood propagation.
class_name ShipLayout
extends RefCounted

const _ShipRoom := preload("res://scripts/shared/ship_room.gd")

## Convenience alias.
const R := _ShipRoom.RoomType
const D := _ShipRoom.DeckLevel

# ── stored layout ──
var rooms: Array[ShipRoom] = []
## Quick lookup: RoomType -> Array[ShipRoom] (some types may have >1 room).
var rooms_by_type: Dictionary = {}


static func build(ship_class: int) -> ShipLayout:
	var layout := ShipLayout.new()
	match ship_class:
		0:  # SCHOONER
			_build_schooner(layout)
		1:  # BRIG
			_build_brig(layout)
		2:  # GALLEY
			_build_galley(layout)
		_:
			_build_brig(layout)
	layout._index_by_type()
	return layout


## Return first room matching a type, or null.
func get_room(room_type: _ShipRoom.RoomType) -> ShipRoom:
	var arr: Variant = rooms_by_type.get(room_type)
	if arr is Array and not arr.is_empty():
		return arr[0] as ShipRoom
	return null


## Return all rooms matching a type.
func get_rooms(room_type: _ShipRoom.RoomType) -> Array:
	return rooms_by_type.get(room_type, []) as Array


## Total crew capacity across all rooms.
func total_capacity() -> int:
	var cap: int = 0
	for room: ShipRoom in rooms:
		cap += room.max_crew
	return cap


func reset_all() -> void:
	for room: ShipRoom in rooms:
		room.reset()


# ── internals ──

func _index_by_type() -> void:
	rooms_by_type.clear()
	for room: ShipRoom in rooms:
		if not rooms_by_type.has(room.type):
			rooms_by_type[room.type] = []
		rooms_by_type[room.type].append(room)


static func _make(layout: ShipLayout, t: _ShipRoom.RoomType, cap: int, deck: _ShipRoom.DeckLevel, pos: Vector2) -> ShipRoom:
	var room := _ShipRoom.new(t, cap, deck)
	room.room_index = layout.rooms.size()
	room.position_on_hull = pos
	layout.rooms.append(room)
	return room


static func _link(a: ShipRoom, b: ShipRoom) -> void:
	if b not in a.adjacent_rooms:
		a.adjacent_rooms.append(b)
	if a not in b.adjacent_rooms:
		b.adjacent_rooms.append(a)


# ═══════════════════════════════════════════════════════════════════════
#  Schooner — 7 rooms, small fast ship
# ═══════════════════════════════════════════════════════════════════════
static func _build_schooner(layout: ShipLayout) -> void:
	#                  type              cap  deck        HUD pos (norm)
	var helm      := _make(layout, R.HELM,             2, D.MAIN,  Vector2(0.50, 0.80))
	var gun_port  := _make(layout, R.GUN_DECK_PORT,    2, D.MAIN,  Vector2(0.20, 0.45))
	var gun_stbd  := _make(layout, R.GUN_DECK_STBD,    2, D.MAIN,  Vector2(0.80, 0.45))
	var rigging   := _make(layout, R.RIGGING,           2, D.UPPER, Vector2(0.50, 0.30))
	var carpenter := _make(layout, R.CARPENTER,         1, D.MAIN,  Vector2(0.50, 0.55))
	var magazine  := _make(layout, R.MAGAZINE,          1, D.LOWER, Vector2(0.50, 0.18))
	var quarters  := _make(layout, R.CREW_QUARTERS,     2, D.LOWER, Vector2(0.50, 0.68))
	# adjacency
	_link(helm, gun_port)
	_link(helm, gun_stbd)
	_link(helm, quarters)
	_link(gun_port, rigging)
	_link(gun_stbd, rigging)
	_link(gun_port, carpenter)
	_link(gun_stbd, carpenter)
	_link(carpenter, magazine)
	_link(carpenter, quarters)


# ═══════════════════════════════════════════════════════════════════════
#  Brig — 10 rooms, balanced warship
# ═══════════════════════════════════════════════════════════════════════
static func _build_brig(layout: ShipLayout) -> void:
	var helm      := _make(layout, R.HELM,             2, D.MAIN,  Vector2(0.50, 0.85))
	var gun_port  := _make(layout, R.GUN_DECK_PORT,    2, D.MAIN,  Vector2(0.15, 0.45))
	var gun_stbd  := _make(layout, R.GUN_DECK_STBD,    2, D.MAIN,  Vector2(0.85, 0.45))
	var rigging   := _make(layout, R.RIGGING,           2, D.UPPER, Vector2(0.50, 0.25))
	var carpenter := _make(layout, R.CARPENTER,         2, D.MAIN,  Vector2(0.50, 0.55))
	var pumps     := _make(layout, R.PUMPS,             1, D.LOWER, Vector2(0.35, 0.65))
	var quarters  := _make(layout, R.CREW_QUARTERS,     2, D.LOWER, Vector2(0.50, 0.72))
	var magazine  := _make(layout, R.MAGAZINE,          1, D.LOWER, Vector2(0.50, 0.15))
	var galley    := _make(layout, R.GALLEY_KITCHEN,    1, D.LOWER, Vector2(0.65, 0.65))
	var sickbay   := _make(layout, R.SICKBAY,           1, D.LOWER, Vector2(0.35, 0.78))
	# adjacency
	_link(helm, gun_port)
	_link(helm, gun_stbd)
	_link(helm, quarters)
	_link(gun_port, rigging)
	_link(gun_stbd, rigging)
	_link(gun_port, carpenter)
	_link(gun_stbd, carpenter)
	_link(carpenter, pumps)
	_link(carpenter, magazine)
	_link(pumps, quarters)
	_link(galley, quarters)
	_link(galley, magazine)
	_link(sickbay, quarters)


# ═══════════════════════════════════════════════════════════════════════
#  Galley — 14 rooms, heavy warship with advanced sections
# ═══════════════════════════════════════════════════════════════════════
static func _build_galley(layout: ShipLayout) -> void:
	var helm       := _make(layout, R.HELM,              2, D.MAIN,  Vector2(0.50, 0.90))
	var officers   := _make(layout, R.OFFICERS_QUARTERS, 1, D.MAIN,  Vector2(0.50, 0.82))
	var gun_port_u := _make(layout, R.GUN_DECK_PORT,     2, D.MAIN,  Vector2(0.12, 0.50))
	var gun_port_l := _make(layout, R.GUN_DECK_PORT,     2, D.LOWER, Vector2(0.12, 0.60))
	var gun_stbd_u := _make(layout, R.GUN_DECK_STBD,     2, D.MAIN,  Vector2(0.88, 0.50))
	var gun_stbd_l := _make(layout, R.GUN_DECK_STBD,     2, D.LOWER, Vector2(0.88, 0.60))
	var rigging    := _make(layout, R.RIGGING,            2, D.UPPER, Vector2(0.50, 0.22))
	var carpenter  := _make(layout, R.CARPENTER,          2, D.MAIN,  Vector2(0.50, 0.55))
	var pumps      := _make(layout, R.PUMPS,              2, D.LOWER, Vector2(0.35, 0.68))
	var magazine   := _make(layout, R.MAGAZINE,           2, D.LOWER, Vector2(0.50, 0.15))
	var galley_k   := _make(layout, R.GALLEY_KITCHEN,     1, D.LOWER, Vector2(0.65, 0.68))
	var sickbay    := _make(layout, R.SICKBAY,            1, D.LOWER, Vector2(0.35, 0.78))
	var brig_jail  := _make(layout, R.BRIG_JAIL,          2, D.LOWER, Vector2(0.65, 0.78))
	var quarters   := _make(layout, R.CREW_QUARTERS,      3, D.LOWER, Vector2(0.50, 0.72))
	# adjacency — upper / main deck
	_link(helm, officers)
	_link(officers, gun_port_u)
	_link(officers, gun_stbd_u)
	_link(gun_port_u, rigging)
	_link(gun_stbd_u, rigging)
	_link(gun_port_u, carpenter)
	_link(gun_stbd_u, carpenter)
	# upper ↔ lower gun decks
	_link(gun_port_u, gun_port_l)
	_link(gun_stbd_u, gun_stbd_l)
	# lower deck connections
	_link(gun_port_l, carpenter)
	_link(gun_stbd_l, carpenter)
	_link(carpenter, pumps)
	_link(carpenter, magazine)
	_link(pumps, quarters)
	_link(magazine, galley_k)
	_link(galley_k, quarters)
	_link(galley_k, brig_jail)
	_link(sickbay, quarters)
	_link(sickbay, brig_jail)
	_link(brig_jail, quarters)

	# Differentiate the two port/stbd gun deck rooms for display.
	gun_port_u.display_name = "Guns Port (Upper)"
	gun_port_l.display_name = "Guns Port (Lower)"
	gun_stbd_u.display_name = "Guns Stbd (Upper)"
	gun_stbd_l.display_name = "Guns Stbd (Lower)"
