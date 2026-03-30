@tool
extends BTAction
## Fallback hold / gentle circle — priority 8.


func _generate_name() -> String:
	return "Naval Hold"


func _tick(delta: float) -> int:
	var c: NavalBotController = blackboard.get_var(&"controller", null) as NavalBotController
	if c == null:
		return BT.Status.FAILURE
	return c.limbo_tick_hold(delta)
