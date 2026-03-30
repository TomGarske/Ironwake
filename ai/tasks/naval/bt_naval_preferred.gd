@tool
extends BTAction
## Maintain preferred band + align — priority 5.


func _generate_name() -> String:
	return "Naval Preferred"


func _tick(delta: float) -> int:
	var c: NavalBotController = blackboard.get_var(&"controller", null) as NavalBotController
	if c == null:
		return BT.Status.FAILURE
	return c.limbo_tick_preferred(delta)
