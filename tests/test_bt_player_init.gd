## Standalone test: verifies LimboAI BTPlayer initialization.
## Run as main scene (F6) — paste FULL output.
extends Node2D


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("===== LimboAI Init Test =====")

	if not ClassDB.class_exists(&"BehaviorTree"):
		print("ABORT: BehaviorTree class missing")
		return

	var tree_script = load("res://scripts/shared/naval_bt_duel_tree.gd")
	var tree = tree_script.build()
	if tree == null:
		print("ABORT: build() returned null")
		return
	print("PASS: tree built")

	# Use self as scene root — get_tree().current_scene can be null.
	var scene_root: Node = self
	print("scene_root = %s (self)" % str(scene_root))

	# ── Direct BehaviorTree.instantiate() ──
	# From C++ source: instantiate(agent, blackboard, instance_owner, scene_root) — 4 args.
	print("")
	print("--- Direct BehaviorTree.instantiate(agent, bb, owner, scene_root) ---")

	var bb = ClassDB.instantiate(&"Blackboard") if ClassDB.class_exists(&"Blackboard") else null
	if bb == null:
		print("ABORT: cannot create Blackboard")
		return
	bb.call("set_var", &"controller", self)

	var tree_inst = tree.call("instantiate", scene_root, bb, scene_root, scene_root)
	if tree_inst != null:
		print("  PASS: instantiate returned %s" % tree_inst.get_class())
	else:
		print("  FAIL: instantiate returned null")
		print("===== Test Complete =====")
		return

	# ── BTPlayer test ──
	print("")
	print("--- BTPlayer (add_child, set owner, then set behavior_tree) ---")
	if not ClassDB.class_exists(&"BTPlayer"):
		print("ABORT: BTPlayer class missing")
		return

	var player: Node = ClassDB.instantiate(&"BTPlayer")
	player.name = "BTPlayerTest"
	player.set("update_mode", 2)   # MANUAL

	# Step 1: add_child — _ready fires, no behavior_tree → _try_initialize returns silently.
	add_child(player)
	print("  add_child done, player in tree = %s" % player.is_inside_tree())

	# Step 2: set owner BEFORE behavior_tree.
	# self is an ancestor (self → player), so set_owner succeeds.
	player.owner = scene_root
	print("  player.owner = %s (expected %s, match = %s)" % [
		str(player.owner), str(scene_root), str(player.owner == scene_root)])

	# Step 3: set behavior_tree — setter calls _try_initialize().
	# _try_initialize: behavior_tree valid, _get_scene_root() → get_owner() → scene_root ✓
	player.set("behavior_tree", tree)
	print("  behavior_tree set")

	# Step 4: seed blackboard.
	var player_bb = player.get("blackboard")
	if player_bb != null:
		player_bb.call("set_var", &"controller", self)
		print("  blackboard seeded with controller")
	else:
		print("  FAIL: blackboard is null")

	# Step 5: update tick.
	print("  calling player.update(0.016)...")
	player.call("update", 0.016)
	print("  update returned (C++ error above = init failed, no error = PASS)")

	player.queue_free()

	print("")
	print("===== Test Complete =====")
