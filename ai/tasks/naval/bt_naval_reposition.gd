@tool
extends BTAction
## Post-volley reposition — priority 4.


func _generate_name() -> String:
	return "Naval Reposition"


func _tick(delta: float) -> int:
	var c: NavalBotController = blackboard.get_var(&"controller", null) as NavalBotController
	if c == null:
		return BT.Status.FAILURE
	return c.limbo_tick_reposition(delta)
