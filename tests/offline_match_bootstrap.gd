extends Node

## Same as home **Test**: offline Fleet Battle. MCP: run_project + scene → wait → get_debug_output → stop_project.


func _ready() -> void:
	call_deferred("_enter")


func _enter() -> void:
	GameManager.start_offline_test_match("fleet_battle")
