@tool
extends BTAction
## Stuck recovery — priority 1 (NavalBotController.limbo_tick_recover).


func _generate_name() -> String:
	return "Naval Recover"


func _tick(delta: float) -> int:
	var c: NavalBotController = blackboard.get_var(&"controller", null) as NavalBotController
	if c == null:
		return BT.Status.FAILURE
	return c.limbo_tick_recover(delta)
