## Builds the naval duel behavior tree for LimboAI (req-ai-naval-bot-v1, PLAN §2.6).
class_name NavalBTDuelTree
extends RefCounted

const _Recover := preload("res://ai/tasks/naval/bt_naval_recover.gd")
const _Fire := preload("res://ai/tasks/naval/bt_naval_fire.gd")
const _Breakaway := preload("res://ai/tasks/naval/bt_naval_breakaway.gd")
const _Reposition := preload("res://ai/tasks/naval/bt_naval_reposition.gd")
const _Preferred := preload("res://ai/tasks/naval/bt_naval_preferred.gd")
const _Approach := preload("res://ai/tasks/naval/bt_naval_approach.gd")
const _Establish := preload("res://ai/tasks/naval/bt_naval_establish.gd")
const _Hold := preload("res://ai/tasks/naval/bt_naval_hold.gd")


static func build() -> BehaviorTree:
	var root := BTSelector.new()
	root.custom_name = "NavalDuel"

	root.add_child(_Recover.new())
	root.add_child(_Fire.new())
	root.add_child(_Breakaway.new())
	root.add_child(_Reposition.new())
	root.add_child(_Preferred.new())
	root.add_child(_Approach.new())
	root.add_child(_Establish.new())
	root.add_child(_Hold.new())

	var tree := BehaviorTree.new()
	tree.set_root_task(root)
	return tree
