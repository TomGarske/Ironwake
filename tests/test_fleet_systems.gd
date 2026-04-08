## Standalone test: verifies fleet registry, win conditions, fleet spawner,
## and wingman controller initialization.
## Run as main scene (F6) — check output for PASS/FAIL.
extends Node2D


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("===== Fleet Systems Test =====")
	print("")
	_test_fleet_registry()
	_test_win_conditions()
	_test_fleet_spawner()
	_test_wingman_controller()
	_test_battery_sides()
	_test_rout_controller()
	_test_pve_scoreboard()
	_test_minimap_renderer()
	_test_fleet_command_menu()
	_test_crew_ai_controller()
	print("")
	print("===== Test Complete =====")


func _test_fleet_registry() -> void:
	print("--- FleetRegistry ---")
	var reg := FleetRegistry.new()

	# No fleets registered — should be hostile to everyone.
	assert(not reg.has_fleets(), "FAIL: has_fleets should be false when empty")
	assert(not reg.are_allies(0, 1), "FAIL: unregistered ships should not be allies")
	print("  PASS: empty registry treats all as hostile")

	# Register two fleets on different teams.
	reg.register_fleet(0, [0, 1, 2], 0, Color.BLUE)
	reg.register_fleet(1, [3, 4, 5], 1, Color.RED)

	assert(reg.has_fleets(), "FAIL: has_fleets should be true")
	assert(reg.are_allies(0, 1), "FAIL: ships 0,1 should be allies (same fleet)")
	assert(reg.are_allies(0, 2), "FAIL: ships 0,2 should be allies (same fleet)")
	assert(not reg.are_allies(0, 3), "FAIL: ships 0,3 should be enemies (diff teams)")
	assert(not reg.are_allies(1, 4), "FAIL: ships 1,4 should be enemies (diff teams)")
	assert(reg.are_allies(3, 5), "FAIL: ships 3,5 should be allies (same fleet)")
	print("  PASS: ally/enemy detection correct")

	assert(reg.get_team(0) == 0, "FAIL: ship 0 team should be 0")
	assert(reg.get_team(3) == 1, "FAIL: ship 3 team should be 1")
	assert(reg.get_team(99) == -1, "FAIL: unregistered ship should return team -1")
	print("  PASS: team lookups correct")

	var enemies: Array[int] = reg.get_enemies_of(0, [0, 1, 2, 3, 4, 5])
	assert(enemies.size() == 3, "FAIL: ship 0 should have 3 enemies, got %d" % enemies.size())
	assert(3 in enemies and 4 in enemies and 5 in enemies, "FAIL: enemies should be [3,4,5]")
	print("  PASS: get_enemies_of correct")

	# Alive count.
	var mock_players: Array = []
	for i in range(6):
		mock_players.append({"alive": i != 2})  # ship 2 is dead
	assert(reg.get_fleet_alive_count(0, mock_players) == 2, "FAIL: fleet 0 should have 2 alive")
	assert(reg.get_fleet_alive_count(1, mock_players) == 3, "FAIL: fleet 1 should have 3 alive")
	print("  PASS: alive count correct")

	# Remove ship.
	reg.remove_ship(1)
	assert(reg.get_fleet_id(1) == -1, "FAIL: removed ship should have no fleet")
	print("  PASS: remove_ship works")
	print("")


func _test_win_conditions() -> void:
	print("--- WinCondition ---")

	# PVP Kill Win.
	var pvp := WinCondition.PvpKillWin.new()
	pvp.kill_target = 3
	pvp.match_time_limit = 60.0

	var players: Array = [
		{"peer_id": 1},
		{"peer_id": 2},
	]
	var scoreboard: Dictionary = {
		1: {"kills": 0, "deaths": 0},
		2: {"kills": 0, "deaths": 0},
	}
	assert(pvp.check(players, scoreboard, 0.0) == WinCondition.PLAYING, "FAIL: should be PLAYING with 0 kills")

	scoreboard[1]["kills"] = 3
	assert(pvp.check(players, scoreboard, 0.0) == 0, "FAIL: player 0 should win with 3 kills")
	print("  PASS: PvpKillWin kill-target works")

	scoreboard[1]["kills"] = 0
	scoreboard[2]["kills"] = 0
	assert(pvp.check(players, scoreboard, 60.0) == WinCondition.DRAW, "FAIL: should be DRAW at time limit with tied kills")
	print("  PASS: PvpKillWin time-limit draw works")

	# PVE Elimination Win.
	var reg := FleetRegistry.new()
	reg.register_fleet(0, [0, 1, 2, 3, 4], 0)
	reg.register_fleet(1, [5, 6, 7, 8, 9], 1)

	var pve := WinCondition.PveEliminationWin.new()
	pve.fleet_registry = reg

	var pve_players: Array = []
	for i in range(10):
		pve_players.append({"alive": true, "peer_id": i})

	assert(pve.check(pve_players, {}, 0.0) == WinCondition.PLAYING, "FAIL: should be PLAYING with all alive")

	# Kill 3 enemy ships (indices 5, 6, 7).
	pve_players[5]["alive"] = false
	pve_players[6]["alive"] = false
	pve_players[7]["alive"] = false
	var result: int = pve.check(pve_players, {}, 0.0)
	assert(result != WinCondition.PLAYING, "FAIL: should trigger win when enemy fleet loses 3/5")
	print("  PASS: PveEliminationWin triggers at >50%% losses")
	print("")


func _test_fleet_spawner() -> void:
	print("--- FleetSpawner ---")
	var center := Vector2(2000.0, 2000.0)
	var heading := Vector2(0.0, -1.0)
	var comp: Array[int] = FleetSpawner.DEFAULT_FLEET_COMPOSITION

	var spawns: Array[Dictionary] = FleetSpawner.spawn_fleet_formation(center, heading, comp)
	assert(spawns.size() == 5, "FAIL: should spawn 5 ships, got %d" % spawns.size())
	print("  PASS: spawns correct number of ships")

	# Flagship should be at center.
	assert(absf(spawns[0].wx - center.x) < 1.0, "FAIL: flagship not at center X")
	assert(absf(spawns[0].wy - center.y) < 1.0, "FAIL: flagship not at center Y")
	print("  PASS: flagship at center")

	# Wingmen should be behind and to the sides.
	for i in range(1, spawns.size()):
		var behind: float = spawns[i].wy - center.y  # positive = south of center
		assert(behind > 0.0, "FAIL: wingman %d should be behind flagship (south)" % i)
	print("  PASS: wingmen positioned behind flagship")

	# Fleet centers.
	var centers: Dictionary = FleetSpawner.compute_fleet_centers(center)
	var dist: float = (centers["player_center"] as Vector2).distance_to(centers["enemy_center"] as Vector2)
	assert(dist > 3000.0, "FAIL: fleets should be >3000 apart, got %.0f" % dist)
	print("  PASS: fleet centers are %.0f apart (outside combat range)" % dist)
	print("")


func _test_wingman_controller() -> void:
	print("--- WingmanController ---")

	# Just verify the class loads and enums exist.
	var wc := WingmanController.new()
	assert(wc.current_order == WingmanController.FleetOrder.FORM_UP, "FAIL: default order should be FORM_UP")
	assert(WingmanController.ORDER_NAMES.size() == WingmanController.ORDER_COUNT, "FAIL: order names should match ORDER_COUNT")

	wc.set_order(WingmanController.FleetOrder.ATTACK_MY_TARGET)
	assert(wc.current_order == WingmanController.FleetOrder.ATTACK_MY_TARGET, "FAIL: order not set")

	wc.set_order(WingmanController.FleetOrder.HOLD_POSITION)
	assert(wc.current_order == WingmanController.FleetOrder.HOLD_POSITION, "FAIL: order not set")
	print("  PASS: wingman controller orders work")

	wc.free()
	print("")


func _test_battery_sides() -> void:
	print("--- BatteryController Sides ---")

	# Verify all 4 sides have correct perpendicular directions.
	var hull := Vector2(0.0, -1.0)  # Facing north.

	var bat_p := BatteryController.new()
	bat_p.side = BatteryController.BatterySide.PORT
	var perp_p: Vector2 = bat_p._broadside_perp(hull)
	assert(perp_p.dot(Vector2(-1.0, 0.0)) > 0.9, "FAIL: PORT should point left (west)")
	print("  PASS: PORT perpendicular correct")

	var bat_s := BatteryController.new()
	bat_s.side = BatteryController.BatterySide.STARBOARD
	var perp_s: Vector2 = bat_s._broadside_perp(hull)
	assert(perp_s.dot(Vector2(1.0, 0.0)) > 0.9, "FAIL: STARBOARD should point right (east)")
	print("  PASS: STARBOARD perpendicular correct")

	var bat_f := BatteryController.new()
	bat_f.side = BatteryController.BatterySide.FORWARD
	var perp_f: Vector2 = bat_f._broadside_perp(hull)
	assert(perp_f.dot(Vector2(0.0, -1.0)) > 0.9, "FAIL: FORWARD should point ahead (north)")
	print("  PASS: FORWARD perpendicular correct")

	var bat_a := BatteryController.new()
	bat_a.side = BatteryController.BatterySide.AFT
	var perp_a: Vector2 = bat_a._broadside_perp(hull)
	assert(perp_a.dot(Vector2(0.0, 1.0)) > 0.9, "FAIL: AFT should point behind (south)")
	print("  PASS: AFT perpendicular correct")

	# Verify side_label covers all cases.
	assert(bat_p.side_label() == "Port", "FAIL: PORT label")
	assert(bat_s.side_label() == "Starboard", "FAIL: STARBOARD label")
	assert(bat_f.side_label() == "Forward", "FAIL: FORWARD label")
	assert(bat_a.side_label() == "Aft", "FAIL: AFT label")
	print("  PASS: all side labels correct")
	print("")


func _test_rout_controller() -> void:
	print("--- RoutController ---")
	var rout := RoutController.new()

	assert(not rout.is_fleet_routed(0), "FAIL: fleet 0 should not be routed initially")
	assert(not rout.is_fleet_routed(1), "FAIL: fleet 1 should not be routed initially")

	rout.trigger_rout(1)
	assert(rout.is_fleet_routed(1), "FAIL: fleet 1 should be routed after trigger")
	assert(not rout.is_fleet_routed(0), "FAIL: fleet 0 should still not be routed")
	print("  PASS: rout trigger works")

	# Test flee direction.
	var ship_pos := Vector2(100.0, 100.0)
	var enemy_center := Vector2(200.0, 200.0)
	var flee: Vector2 = RoutController.compute_flee_direction(ship_pos, enemy_center)
	assert(flee.dot(Vector2(-1.0, -1.0).normalized()) > 0.9, "FAIL: flee should be away from enemy")
	print("  PASS: flee direction correct")

	# Test centroid.
	var players: Array = [
		{"wx": 100.0, "wy": 100.0, "alive": true},
		{"wx": 200.0, "wy": 200.0, "alive": true},
		{"wx": 300.0, "wy": 300.0, "alive": false},  # dead, should be excluded
	]
	var centroid: Vector2 = RoutController.compute_centroid(players, [0, 1, 2])
	assert(absf(centroid.x - 150.0) < 1.0, "FAIL: centroid X should be 150, got %.1f" % centroid.x)
	assert(absf(centroid.y - 150.0) < 1.0, "FAIL: centroid Y should be 150, got %.1f" % centroid.y)
	print("  PASS: centroid excludes dead ships")

	# Test despawn detection.
	var test_ship: Dictionary = {
		"wx": -600.0, "wy": 100.0, "alive": true,
		"dir": Vector2(-1.0, 0.0),
		"move_speed": 50.0,
	}
	var should_despawn: bool = rout.tick_rout_ship(test_ship, Vector2(-1.0, 0.0), 0.016)
	assert(should_despawn, "FAIL: ship at -600 should despawn (past margin)")
	print("  PASS: despawn detection works")
	print("")


func _test_pve_scoreboard() -> void:
	print("--- PveScoreboard ---")
	var score := PveScoreboard.new()
	score.reset(5)

	assert(score.fleet_ships_total == 5, "FAIL: fleet total should be 5")
	assert(score.fleet_health_fraction() == 1.0, "FAIL: full fleet should be 100%%")
	print("  PASS: initial state correct")

	score.fleet_ships_lost = 2
	assert(absf(score.fleet_health_fraction() - 0.6) < 0.01, "FAIL: 3/5 survived = 60%%")
	print("  PASS: fleet health fraction correct")

	score.record_kill()
	score.record_kill()
	score.record_kill()
	assert(score.team_ships_sunk == 3, "FAIL: should have 3 kills")
	print("  PASS: kill tracking correct")

	# Test accuracy.
	score.team_shots_fired = 100
	score.team_shots_hit = 25
	assert(absf(score.accuracy_percent() - 25.0) < 0.1, "FAIL: accuracy should be 25%%")
	print("  PASS: accuracy calculation correct")

	# Test rating with good performance.
	score.fleet_ships_lost = 0
	score.match_duration = 90.0  # Fast clear.
	var rating: int = score.compute_rating()
	assert(rating == PveScoreboard.Rating.S, "FAIL: perfect fleet + fast clear = S rating, got %s" % score.rating_name())
	print("  PASS: S rating for perfect + fast clear")

	# Test rating with poor performance.
	score.fleet_ships_lost = 4
	score.match_duration = 500.0  # Slow.
	rating = score.compute_rating()
	assert(rating == PveScoreboard.Rating.D, "FAIL: 1/5 survived + slow = D rating, got %s" % score.rating_name())
	print("  PASS: D rating for heavy losses + slow clear")

	# Test time formatting.
	score.match_duration = 185.0
	assert(score.format_time() == "3:05", "FAIL: 185s should format as 3:05, got %s" % score.format_time())
	print("  PASS: time formatting correct")
	print("")


func _test_minimap_renderer() -> void:
	print("--- MinimapRenderer ---")
	var mm := MinimapRenderer.new()
	mm.configure(400, 400, 10.0)

	assert(mm.world_width == 4000.0, "FAIL: world_width should be 4000")
	assert(mm.world_height == 4000.0, "FAIL: world_height should be 4000")
	print("  PASS: configure sets world bounds")

	# World-to-minimap mapping.
	var corner: Vector2 = mm._world_to_minimap(0.0, 0.0)
	assert(corner.x == 0.0 and corner.y == 0.0, "FAIL: (0,0) should map to minimap (0,0)")
	var center: Vector2 = mm._world_to_minimap(2000.0, 2000.0)
	assert(absf(center.x - 100.0) < 1.0, "FAIL: center should map to minimap (100,100)")
	var far: Vector2 = mm._world_to_minimap(4000.0, 4000.0)
	assert(absf(far.x - 200.0) < 1.0, "FAIL: far corner should map to minimap (200,200)")
	print("  PASS: world-to-minimap coordinate mapping correct")

	# Clamping.
	var oob: Vector2 = mm._world_to_minimap(-500.0, 5000.0)
	assert(oob.x == 0.0, "FAIL: negative X should clamp to 0")
	assert(oob.y == 200.0, "FAIL: over-max Y should clamp to MAP_SIZE")
	print("  PASS: out-of-bounds clamping works")
	print("")


func _test_fleet_command_menu() -> void:
	print("--- FleetCommandMenu ---")
	var menu := FleetCommandMenu.new()

	assert(not menu.is_open, "FAIL: menu should start closed")
	assert(menu.hovered_sector == -1, "FAIL: no sector hovered initially")
	print("  PASS: initial state correct")

	assert(FleetCommandMenu.SECTORS.size() == FleetCommandMenu.SECTOR_COUNT, "FAIL: SECTORS should match SECTOR_COUNT")
	print("  PASS: sector definitions correct")

	# Simulate a quick tap (pressed + released before threshold).
	var vp_center := Vector2(640.0, 360.0)
	var result: int = menu.process_input(0.01, true, true, false, vp_center, vp_center)
	assert(result == -1, "FAIL: should return -1 while key held")
	assert(not menu.is_open, "FAIL: menu should not open before threshold")
	result = menu.process_input(0.0, false, false, true, vp_center, vp_center)
	assert(result == -1, "FAIL: quick tap with no sector hovered should return -1")
	print("  PASS: quick tap does not select sector")

	# Simulate hold past threshold.
	menu.process_input(0.01, true, true, false, vp_center, vp_center)
	menu.process_input(0.25, true, false, false, vp_center + Vector2(0.0, -60.0), vp_center)
	assert(menu.is_open, "FAIL: menu should open after hold threshold")
	assert(menu.hovered_sector >= 0, "FAIL: should have a hovered sector")
	print("  PASS: hold opens radial menu with sector selection")

	# Release to select.
	result = menu.process_input(0.0, false, false, true, vp_center + Vector2(0.0, -60.0), vp_center)
	assert(result >= 0, "FAIL: release on sector should return order index, got %d" % result)
	assert(not menu.is_open, "FAIL: menu should close on release")
	print("  PASS: release selects sector (order %d)" % result)
	print("")


func _test_crew_ai_controller() -> void:
	print("--- CrewAiController ---")

	# Test fire emergency allocation.
	var alloc: Array[int] = CrewAiController._compute_allocation(
		true, false, false, false, false, false, false)
	assert(alloc[4] >= 10, "FAIL: fire should send most crew to REPAIR, got %d" % alloc[4])
	print("  PASS: fire emergency prioritizes repair (%d crew)" % alloc[4])

	# Test flood emergency.
	alloc = CrewAiController._compute_allocation(
		false, false, true, false, false, false, false)  # heavy_flood
	assert(alloc[4] >= 12, "FAIL: heavy flood should max REPAIR, got %d" % alloc[4])
	print("  PASS: heavy flood prioritizes repair (%d crew)" % alloc[4])

	# Test dual emergency.
	alloc = CrewAiController._compute_allocation(
		true, true, true, false, false, false, false)
	assert(alloc[4] >= 14, "FAIL: fire+heavy flood should be all hands on deck, got %d" % alloc[4])
	print("  PASS: dual emergency maxes repair (%d crew)" % alloc[4])

	# Test hull critical.
	alloc = CrewAiController._compute_allocation(
		false, false, false, true, true, false, false)  # needs_repair + critical
	assert(alloc[4] >= 10, "FAIL: critical hull should heavily repair, got %d" % alloc[4])
	print("  PASS: critical hull focuses repair (%d crew)" % alloc[4])

	# Test combat — port battery active.
	alloc = CrewAiController._compute_allocation(
		false, false, false, false, false, true, false)
	assert(alloc[0] >= 6, "FAIL: port combat should crew port guns, got %d" % alloc[0])
	assert(alloc[0] > alloc[1], "FAIL: port should have more crew than stbd")
	print("  PASS: port combat crews port guns (%d vs %d stbd)" % [alloc[0], alloc[1]])

	# Test combat — both batteries active.
	alloc = CrewAiController._compute_allocation(
		false, false, false, false, false, true, true)
	assert(alloc[0] == alloc[1], "FAIL: both batteries should be equal, got %d/%d" % [alloc[0], alloc[1]])
	assert(alloc[0] >= 4, "FAIL: both batteries should have decent crew, got %d" % alloc[0])
	print("  PASS: dual combat evenly crews guns (%d each)" % alloc[0])

	# Test idle — balanced.
	alloc = CrewAiController._compute_allocation(
		false, false, false, false, false, false, false)
	assert(alloc[0] == alloc[1] and alloc[1] == alloc[2] and alloc[2] == alloc[3] and alloc[3] == alloc[4],
		"FAIL: idle should be balanced, got %s" % str(alloc))
	print("  PASS: idle distributes evenly (%s)" % str(alloc))

	# Test battery_wants_crew.
	var bat := BatteryController.new()
	bat.state = BatteryController.BatteryState.RELOADING
	assert(CrewAiController._battery_wants_crew(bat), "FAIL: RELOADING battery should want crew")
	bat.state = BatteryController.BatteryState.IDLE
	assert(not CrewAiController._battery_wants_crew(bat), "FAIL: IDLE battery should not want crew")
	bat.state = BatteryController.BatteryState.DISABLED
	assert(not CrewAiController._battery_wants_crew(bat), "FAIL: DISABLED battery should not want crew")
	print("  PASS: battery_wants_crew correct for all states")
	print("")
