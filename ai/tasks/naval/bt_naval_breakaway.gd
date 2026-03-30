@tool
extends BTAction
## Break away when too close — priority 3.


func _generate_name() -> String:
	return "Naval Breakaway"


func _tick(delta: float) -> int:
	var c: NavalBotController = blackboard.get_var(&"controller", null) as NavalBotController
	if c == null:
		return BT.Status.FAILURE
	return c.limbo_tick_breakaway(delta)
