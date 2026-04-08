extends Node

## Offline Ironwake duel (naval arena). MCP smoke for ironwake_arena.tscn load path.


func _ready() -> void:
	call_deferred("_enter")


func _enter() -> void:
	GameManager.start_offline_test_match("ironwake")
