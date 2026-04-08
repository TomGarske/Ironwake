extends Node

## Validates `GameManager` modes and offline setup. MCP: run_project + this scene → get_debug_output → stop_project.


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var errs: PackedStringArray = []
	if GameManager == null:
		errs.append("GameManager autoload missing")
		_finish(errs)
		return

	if GameManager.get_game_modes().is_empty():
		errs.append("GAME_MODES is empty")

	for mid: String in ["ironwake", "fleet_battle"]:
		var mode: Dictionary = GameManager.get_game_mode(mid)
		if mode.is_empty():
			errs.append("missing game mode: %s" % mid)
			continue
		var p: String = str(mode.get("scene_path", ""))
		if p.is_empty() or not ResourceLoader.exists(p):
			errs.append("mode %s scene missing: %s" % [mid, p])

	GameManager.reset()
	GameManager.setup_offline_test()
	if GameManager.players.size() != 2:
		errs.append("setup_offline_test: expected 2 players, got %d" % GameManager.players.size())
	if GameManager.match_phase != GameManager.MatchPhase.IN_MATCH:
		errs.append("setup_offline_test: expected MatchPhase.IN_MATCH")

	GameManager.reset()
	if not GameManager.players.is_empty():
		errs.append("reset() should clear players")

	_finish(errs)


func _finish(errs: PackedStringArray) -> void:
	if errs.is_empty():
		print("GAME_FLOW_SMOKE: PASS")
	else:
		for e: String in errs:
			push_error("GAME_FLOW_SMOKE: %s" % e)
		print("GAME_FLOW_SMOKE: FAIL (%d)" % errs.size())
