@tool
extends BTAction
## Establish broadside when in range — priority 7.


func _generate_name() -> String:
	return "Naval Establish"


func _tick(delta: float) -> int:
	var c: NavalBotController = blackboard.get_var(&"controller", null) as NavalBotController
	if c == null:
		return BT.Status.FAILURE
	return c.limbo_tick_establish(delta)
