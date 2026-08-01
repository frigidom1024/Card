class_name MobInstance
extends RefCounted

var data: MobData
var stats: CombatStats
var action_index: int = 0


func _init(mob_data: MobData) -> void:
	data = mob_data
	if data.base_stats:
		stats = CombatStats.from_data(data.base_stats)
	else:
		push_error("MobData[%s] is missing base_stats" % data.mob_name)


func next_action() -> MobAction:
	if data.actions.is_empty():
		return null
	var action := data.actions[action_index]
	action_index = (action_index + 1) % data.actions.size()
	return action


func get_next_action() -> MobAction:
	return next_action()


func duplicate_for_encounter() -> MobInstance:
	var copy := MobInstance.new(data)
	copy.stats = stats.duplicate_runtime() if stats else null
	copy.action_index = 0
	return copy


func take_damage(amount: int) -> int:
	return stats.take_damage(amount) if stats else 0


func is_alive() -> bool:
	return stats != null and stats.is_alive()
