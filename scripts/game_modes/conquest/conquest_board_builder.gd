## conquest_board_builder.gd
## Builds the classic Risk territory graph and maps territories to world-space positions.
##
## All 42 classic Risk territories are defined explicitly.
## Region groupings and adjacency match the standard Risk board.
## World positions are in the 4000×4000 coordinate space used by iso_arena.
##
## Assumptions:
##   - No globe or hex system exists in the project.
##   - The Conquest map uses a flat 2D world space (4000×4000 world units).
##   - Territory centers are fixed map positions; the board does not change per match.

const ConquestData := preload("res://scripts/game_modes/conquest/conquest_data.gd")


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns a fully built ConquestGameState with territories and regions populated.
## Ownership, armies, and player data are NOT set here — that is done by the
## game manager during setup.
static func build() -> ConquestData.ConquestGameState:
	var state := ConquestData.ConquestGameState.new()
	_build_regions(state)
	_build_territories(state)
	_compute_sphere_positions(state)
	_validate(state)
	return state


## Real-world lat/lon coordinates for each territory center.
## Converted to unit sphere: -X = prime meridian front, Y = north pole.
static var TERRITORY_COORDS: Dictionary = {
	# North America
	"alaska":              [-155.0, 63.0],
	"northwest_territory": [-110.0, 62.0],
	"greenland":           [-42.0,  72.0],
	"alberta":             [-115.0, 52.0],
	"ontario":             [-85.0,  50.0],
	"quebec":              [-72.0,  52.0],
	"western_us":          [-110.0, 38.0],
	"eastern_us":          [-82.0,  35.0],
	"central_america":     [-90.0,  15.0],
	# South America
	"venezuela":           [-66.0,   8.0],
	"peru":                [-76.0, -10.0],
	"brazil":              [-50.0, -10.0],
	"argentina":           [-64.0, -35.0],
	# Europe
	"iceland":             [-19.0,  65.0],
	"great_britain":       [ -2.0,  54.0],
	"scandinavia":         [ 15.0,  62.0],
	"northern_europe":     [ 15.0,  52.0],
	"western_europe":      [  2.0,  46.0],
	"southern_europe":     [ 15.0,  42.0],
	"ukraine":             [ 35.0,  50.0],
	# Africa
	"north_africa":        [  5.0,  28.0],
	"egypt":               [ 31.0,  27.0],
	"east_africa":         [ 38.0,  -2.0],
	"congo":               [ 20.0,  -3.0],
	"south_africa":        [ 25.0, -30.0],
	"madagascar":          [ 47.0, -19.0],
	# Asia
	"ural":                [ 58.0,  58.0],
	"siberia":             [ 90.0,  62.0],
	"yakutsk":             [120.0,  63.0],
	"kamchatka":           [160.0,  56.0],
	"irkutsk":             [105.0,  55.0],
	"mongolia":            [105.0,  46.0],
	"japan":               [138.0,  36.0],
	"china":               [105.0,  35.0],
	"afghanistan":         [ 67.0,  33.0],
	"middle_east":         [ 44.0,  30.0],
	"india":               [ 78.0,  22.0],
	"siam":                [100.0,  15.0],
	# Australia
	"indonesia":           [115.0,  -5.0],
	"new_guinea":          [145.0,  -6.0],
	"western_australia":   [125.0, -25.0],
	"eastern_australia":   [148.0, -25.0],
}

static func _compute_sphere_positions(state: ConquestData.ConquestGameState) -> void:
	for t in state.territories.values():
		var coords: Array = TERRITORY_COORDS.get(t.territory_id, [0.0, 0.0])
		var lon_deg: float = float(coords[0])
		var lat_deg: float = float(coords[1])
		var lon_rad: float = deg_to_rad(lon_deg)
		var lat_rad: float = deg_to_rad(lat_deg)
		# Godot SphereMesh convention: -X = prime meridian, +Y = north pole, -Z = 90E.
		t.sphere_pos = Vector3(
			-cos(lat_rad) * cos(lon_rad),
			sin(lat_rad),
			-cos(lat_rad) * sin(lon_rad)
		).normalized()


# ---------------------------------------------------------------------------
# Region definitions (classic Risk continent bonuses)
# ---------------------------------------------------------------------------
static func _build_regions(state: ConquestData.ConquestGameState) -> void:
	var defs: Array[Dictionary] = [
		{ "id": "north_america", "name": "North America", "bonus": 5,
		  "territories": [
			"alaska","northwest_territory","greenland","alberta","ontario",
			"quebec","western_us","eastern_us","central_america"
		  ]
		},
		{ "id": "south_america", "name": "South America", "bonus": 2,
		  "territories": ["venezuela","peru","brazil","argentina"]
		},
		{ "id": "europe", "name": "Europe", "bonus": 5,
		  "territories": [
			"iceland","great_britain","western_europe","southern_europe",
			"northern_europe","scandinavia","ukraine"
		  ]
		},
		{ "id": "africa", "name": "Africa", "bonus": 3,
		  "territories": [
			"north_africa","egypt","east_africa","congo","south_africa","madagascar"
		  ]
		},
		{ "id": "asia", "name": "Asia", "bonus": 7,
		  "territories": [
			"ural","siberia","yakutsk","kamchatka","irkutsk","mongolia",
			"japan","china","afghanistan","middle_east","india","siam"
		  ]
		},
		{ "id": "australia", "name": "Australia", "bonus": 2,
		  "territories": ["indonesia","new_guinea","western_australia","eastern_australia"]
		},
	]

	for d in defs:
		var ids: Array[String] = []
		for t in d["territories"]:
			ids.append(str(t))
		var r := ConquestData.ConquestRegion.new(
			str(d["id"]),
			str(d["name"]),
			ids,
			int(d["bonus"])
		)
		state.regions[r.region_id] = r


# ---------------------------------------------------------------------------
# Territory definitions
# ---------------------------------------------------------------------------
# Each entry: [ id, display_name, region_id, [adjacency...], cx, cy ]
# World coordinates: X = 0-4000 (west→east), Y = 0-4000 (north→south)
static func _build_territories(state: ConquestData.ConquestGameState) -> void:
	# Positions derived from real-world lat/lon using:
	#   x = 1400 + (lon_deg / 170.0) * 1400
	#   y = (72.0 - lat_deg) / 134.0 * 1800
	var defs: Array[Array] = [
		# ── North America ──────────────────────────────────────────────────
		["alaska",             "Alaska",              "north_america",
			["northwest_territory","alberta","kamchatka"],
			124.0, 121.0],
		["northwest_territory","Northwest Territory",  "north_america",
			["alaska","alberta","ontario","greenland"],
			494.0, 134.0],
		["greenland",          "Greenland",           "north_america",
			["northwest_territory","ontario","quebec","iceland"],
			1054.0, 20.0],
		["alberta",            "Alberta",             "north_america",
			["alaska","northwest_territory","ontario","western_us"],
			452.0, 255.0],
		["ontario",            "Ontario",             "north_america",
			["northwest_territory","alberta","greenland","quebec","western_us","eastern_us"],
			700.0, 295.0],
		["quebec",             "Quebec",              "north_america",
			["greenland","ontario","eastern_us"],
			807.0, 295.0],
		["western_us",         "Western United States","north_america",
			["alberta","ontario","eastern_us","central_america"],
			494.0, 456.0],
		["eastern_us",         "Eastern United States","north_america",
			["ontario","quebec","western_us","central_america"],
			724.0, 496.0],
		["central_america",    "Central America",     "north_america",
			["western_us","eastern_us","venezuela"],
			658.0, 765.0],

		# ── South America ──────────────────────────────────────────────────
		["venezuela",          "Venezuela",           "south_america",
			["central_america","peru","brazil"],
			856.0, 859.0],
		["peru",               "Peru",                "south_america",
			["venezuela","brazil","argentina"],
			774.0, 1101.0],
		["brazil",             "Brazil",              "south_america",
			["venezuela","peru","argentina","north_africa"],
			988.0, 1101.0],
		["argentina",          "Argentina",           "south_america",
			["peru","brazil"],
			872.0, 1437.0],

		# ── Europe ─────────────────────────────────────────────────────────
		["iceland",            "Iceland",             "europe",
			["greenland","great_britain","scandinavia"],
			1244.0, 94.0],
		["great_britain",      "Great Britain",       "europe",
			["iceland","northern_europe","scandinavia","western_europe"],
			1384.0, 241.0],
		["western_europe",     "Western Europe",      "europe",
			["great_britain","northern_europe","southern_europe","north_africa"],
			1416.0, 349.0],
		["southern_europe",    "Southern Europe",     "europe",
			["western_europe","northern_europe","ukraine","north_africa","egypt","middle_east"],
			1524.0, 403.0],
		["northern_europe",    "Northern Europe",     "europe",
			["great_britain","scandinavia","ukraine","western_europe","southern_europe"],
			1524.0, 268.0],
		["scandinavia",        "Scandinavia",         "europe",
			["iceland","great_britain","northern_europe","ukraine"],
			1524.0, 134.0],
		["ukraine",            "Ukraine",             "europe",
			["scandinavia","northern_europe","southern_europe","middle_east","afghanistan","ural"],
			1664.0, 295.0],

		# ── Africa ─────────────────────────────────────────────────────────
		["north_africa",       "North Africa",        "africa",
			["brazil","western_europe","southern_europe","egypt","east_africa","congo"],
			1441.0, 590.0],
		["egypt",              "Egypt",               "africa",
			["southern_europe","middle_east","north_africa","east_africa"],
			1655.0, 604.0],
		["east_africa",        "East Africa",         "africa",
			["egypt","north_africa","congo","south_africa","madagascar","middle_east"],
			1713.0, 994.0],
		["congo",              "Congo",               "africa",
			["north_africa","east_africa","south_africa"],
			1565.0, 1007.0],
		["south_africa",       "South Africa",        "africa",
			["congo","east_africa","madagascar"],
			1606.0, 1370.0],
		["madagascar",         "Madagascar",          "africa",
			["east_africa","south_africa"],
			1787.0, 1222.0],

		# ── Asia ───────────────────────────────────────────────────────────
		["ural",               "Ural",                "asia",
			["ukraine","afghanistan","siberia","china"],
			1878.0, 188.0],
		["siberia",            "Siberia",             "asia",
			["ural","yakutsk","irkutsk","mongolia","china"],
			2141.0, 134.0],
		["yakutsk",            "Yakutsk",             "asia",
			["siberia","kamchatka","irkutsk"],
			2388.0, 121.0],
		["kamchatka",          "Kamchatka",           "asia",
			["yakutsk","irkutsk","mongolia","japan","alaska"],
			2718.0, 215.0],
		["irkutsk",            "Irkutsk",             "asia",
			["siberia","yakutsk","kamchatka","mongolia"],
			2265.0, 228.0],
		["mongolia",           "Mongolia",            "asia",
			["siberia","irkutsk","kamchatka","china","japan"],
			2265.0, 349.0],
		["japan",              "Japan",               "asia",
			["mongolia","kamchatka"],
			2537.0, 483.0],
		["china",              "China",               "asia",
			["ural","siberia","mongolia","afghanistan","india","siam"],
			2265.0, 496.0],
		["afghanistan",        "Afghanistan",         "asia",
			["ukraine","ural","china","middle_east","india"],
			1952.0, 523.0],
		["middle_east",        "Middle East",         "asia",
			["ukraine","southern_europe","egypt","east_africa","afghanistan","india"],
			1763.0, 564.0],
		["india",              "India",               "asia",
			["china","middle_east","afghanistan","siam"],
			2043.0, 671.0],
		["siam",     "Siam",      "asia",
			["china","india","indonesia"],
			2224.0, 765.0],

		# ── Australia ──────────────────────────────────────────────────────
		["indonesia",          "Indonesia",           "australia",
			["siam","new_guinea","western_australia"],
			2347.0, 1034.0],
		["new_guinea",         "New Guinea",          "australia",
			["indonesia","western_australia","eastern_australia"],
			2594.0, 1047.0],
		["western_australia",  "Western Australia",   "australia",
			["indonesia","new_guinea","eastern_australia"],
			2429.0, 1303.0],
		["eastern_australia",  "Eastern Australia",   "australia",
			["western_australia","new_guinea"],
			2619.0, 1303.0],
	]

	for d in defs:
		var adj: Array[String] = []
		for a in (d[3] as Array):
			adj.append(str(a))
		var t := ConquestData.ConquestTerritory.new(
			str(d[0]),
			str(d[1]),
			str(d[2]),
			adj,
			float(d[4]),
			float(d[5])
		)
		state.territories[t.territory_id] = t


# ---------------------------------------------------------------------------
# Validation (called in debug builds; also used by tests)
# ---------------------------------------------------------------------------
static func _validate(state: ConquestData.ConquestGameState) -> void:
	var errors: PackedStringArray = []

	# All 42 territories must exist.
	if state.territories.size() != 42:
		errors.append("Expected 42 territories, got %d" % state.territories.size())

	# All 6 regions must exist.
	if state.regions.size() != 6:
		errors.append("Expected 6 regions, got %d" % state.regions.size())

	# Each territory in a region must exist as a territory key.
	for region in state.regions.values():
		for tid in region.territory_ids:
			if not state.territories.has(tid):
				errors.append("Region '%s' references unknown territory '%s'" % [region.region_id, tid])

	# Each territory's region_id must match a known region.
	for t in state.territories.values():
		if not state.regions.has(t.region_id):
			errors.append("Territory '%s' has unknown region_id '%s'" % [t.territory_id, t.region_id])

	# Adjacency symmetry: if A lists B, B must list A.
	for t in state.territories.values():
		for adj_id in t.adjacent_territory_ids:
			if not state.territories.has(adj_id):
				errors.append("Territory '%s' adj '%s' not found" % [t.territory_id, adj_id])
				continue
			var adj_t: ConquestData.ConquestTerritory = state.territories[adj_id]
			if not adj_t.adjacent_territory_ids.has(t.territory_id):
				errors.append("Adjacency not symmetric: '%s'<->'%s'" % [t.territory_id, adj_id])

	# Territory counts per region must match region.territory_ids.
	for region in state.regions.values():
		var counted: int = 0
		for t in state.territories.values():
			if t.region_id == region.region_id:
				counted += 1
		if counted != region.territory_ids.size():
			errors.append(
				"Region '%s' declares %d territories but %d territories have that region_id"
				% [region.region_id, region.territory_ids.size(), counted]
			)

	if not errors.is_empty():
		for e in errors:
			push_error("[ConquestBoardBuilder] VALIDATION ERROR: %s" % e)
	else:
		DebugOverlay.log_message("[ConquestBoardBuilder] Board validation PASS — 42 territories, 6 regions.")
