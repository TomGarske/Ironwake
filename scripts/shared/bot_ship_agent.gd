## Thin Node2D wrapper around a ship dictionary for LimboAI agent integration.
## Syncs global_position from the dictionary each frame so BT tasks can use
## the standard agent.global_position pattern.  (req-ai-naval-bot-v1)
class_name BotShipAgent
extends Node2D

## Reference to the ship dictionary in the _players array.
var ship_dict: Dictionary = {}

## Convenience accessors for BT tasks.
func get_ship_pos() -> Vector2:
	return Vector2(float(ship_dict.get("wx", 0.0)), float(ship_dict.get("wy", 0.0)))

func get_ship_dir() -> Vector2:
	var d: Vector2 = ship_dict.get("dir", Vector2.RIGHT)
	if d.length_squared() < 0.0001:
		return Vector2.RIGHT
	return d.normalized()

func get_speed() -> float:
	return float(ship_dict.get("move_speed", 0.0))

func get_angular_velocity() -> float:
	return float(ship_dict.get("angular_velocity", 0.0))

func get_helm() -> Variant:
	return ship_dict.get("helm")

func get_sail() -> Variant:
	return ship_dict.get("sail")

func get_battery_port() -> Variant:
	return ship_dict.get("battery_port")

func get_battery_stbd() -> Variant:
	return ship_dict.get("battery_stbd")

func is_alive() -> bool:
	return bool(ship_dict.get("alive", false))

## Whirlpool AI hooks (req-whirlpool-arena-v1 §21).
func get_whirlpool_ring() -> int:
	return int(ship_dict.get("_whirlpool_ring", 0))

func is_in_whirlpool() -> bool:
	return get_whirlpool_ring() > 0

func is_whirlpool_captured() -> bool:
	return bool(ship_dict.get("_whirlpool_captured", false))

func get_whirlpool_flow_alignment() -> float:
	return float(ship_dict.get("_whirlpool_flow_align", 0.0))

func _process(_delta: float) -> void:
	if ship_dict.is_empty():
		return
	global_position = get_ship_pos()
	rotation = get_ship_dir().angle()
