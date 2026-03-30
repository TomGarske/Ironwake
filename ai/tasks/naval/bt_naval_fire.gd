@tool
extends BTAction
## Broadside fire + reaction delay — priority 2.


func _generate_name() -> String:
	return "Naval Fire"


func _tick(delta: float) -> int:
	var c: NavalBotController = blackboard.get_var(&"controller", null) as NavalBotController
	if c == null:
		return BT.Status.FAILURE
	return c.limbo_tick_fire(delta)
