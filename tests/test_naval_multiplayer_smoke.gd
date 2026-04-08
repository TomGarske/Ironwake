extends Node

## Navigation (motion constants), turn (helm + angular velocity), combat (ballistics + broadside),
## local-sim spawn ring. MCP: run_project + scene → get_debug_output → stop_project.

const NC := preload("res://scripts/shared/naval_combat_constants.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var errs: PackedStringArray = []

	if NC.accel_rate() <= 0.0:
		errs.append("accel_rate should be positive")
	if NC.decel_rate_sails() <= 0.0:
		errs.append("decel_rate_sails should be positive")
	if NC.MAX_SPEED <= NC.QUARTER_SPEED:
		errs.append("MAX_SPEED should exceed QUARTER_SPEED")

	var turn_rate_deg: float = NC.turn_rate_deg_for_speed(25.0)
	if turn_rate_deg <= 0.0:
		errs.append("turn_rate_deg_for_speed(25) should be positive")
	if absf(NC.rudder_effectiveness(1.0)) < 0.01:
		errs.append("rudder_effectiveness at full should be non-trivial")

	var ang_vel: float = 0.0
	for _i in range(40):
		ang_vel = NC.compute_angular_velocity(1.0, 22.0, ang_vel, 1.0 / 60.0, 1.0, 1.0)
	if absf(ang_vel) < 1e-5:
		errs.append("compute_angular_velocity should build non-zero turn with rudder + speed")

	var helm := HelmController.new()
	var helm_dt: float = 1.0 / 60.0
	for _j in range(360):
		helm.process_steer(helm_dt, 1.0, 0.0)
	if absf(helm.rudder_angle) < 0.02 and absf(helm.wheel_position) < 0.02:
		errs.append("HelmController should move rudder/wheel under sustained port input")

	var v: Dictionary = CannonBallistics.initial_velocity(Vector2(0.0, 1.0), 10.0)
	var vx: float = float(v.get("vx", 0.0))
	var vy: float = float(v.get("vy", 0.0))
	var vz: float = float(v.get("vz", 0.0))
	var horiz: float = sqrt(vx * vx + vy * vy)
	if horiz < 100.0:
		errs.append("ballistics horizontal speed implausibly low")
	if absf(vz) < 1.0:
		errs.append("ballistics vz should reflect elevation")

	if not is_equal_approx(NC.broadside_quality(90.0), 1.0):
		errs.append("broadside_quality at beam should be 1.0")

	seed(12345)
	var ring: Array = LocalSimController.compute_spawn_ring(Vector2(20000.0, 20000.0), 800.0, 4)
	if ring.size() != 4:
		errs.append("spawn ring should have 4 ships for total_ships=4")
	else:
		for idx in range(ring.size()):
			var e: Dictionary = ring[idx]
			if not e.has("wx") or not e.has("wy") or not e.has("dir"):
				errs.append("spawn ring entry %d missing wx/wy/dir" % idx)
			var d: Variant = e.get("dir", Vector2.ZERO)
			if d is Vector2 and (d as Vector2).length_squared() < 0.0001:
				errs.append("spawn ring entry %d has zero heading" % idx)

	_finish(errs)


func _finish(errs: PackedStringArray) -> void:
	if errs.is_empty():
		print("NAVAL_MP_SMOKE: PASS")
	else:
		for e: String in errs:
			push_error("NAVAL_MP_SMOKE: %s" % e)
		print("NAVAL_MP_SMOKE: FAIL (%d)" % errs.size())
