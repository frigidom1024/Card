class_name MobInstance
extends RefCounted

var data: MobData
var stats: CombatStats
var action_index: int = 0
# Increased after a RETREAT so an unresolved encounter becomes gradually more dangerous.
var enhancement_stacks: int = 0
var max_enhancement_stacks: int = 2


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


## Makes a surviving echo tougher after the chain fails to defeat it.
## Health increases rather than resetting, so damage from earlier attempts stays
## meaningful while the next attempt is slightly more demanding.
func gain_enhancement() -> bool:
	if enhancement_stacks >= max_enhancement_stacks:
		return false
	enhancement_stacks += 1
	var health_bonus := data.enhancement_hp_bonus if data != null else 0
	if stats != null and health_bonus > 0:
		stats.max_hp += health_bonus
		stats.hp = mini(stats.hp + health_bonus, stats.max_hp)
	return true


func duplicate_for_encounter() -> MobInstance:
	var copy := MobInstance.new(data)
	copy.stats = stats.duplicate_runtime() if stats else null
	copy.action_index = action_index
	copy.enhancement_stacks = enhancement_stacks
	copy.max_enhancement_stacks = max_enhancement_stacks
	return copy


func take_damage(amount: int) -> int:
	return stats.take_damage(amount) if stats else 0


func is_alive() -> bool:
	return stats != null and stats.is_alive()