@tool
extends BTAction
## Close distance with offset — priority 6.


func _generate_name() -> String:
	return "Naval Approach"


func _tick(delta: float) -> int:
	var c: NavalBotController = blackboard.get_var(&"controller", null) as NavalBotController
	if c == null:
		return BT.Status.FAILURE
	return c.limbo_tick_approach(delta)
