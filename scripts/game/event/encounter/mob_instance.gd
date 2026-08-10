class_name MobInstance
extends RefCounted

var data: MobData
var stats: CombatStats
var action_index: int = 0
# Increased after a RETREAT so an unresolved echo becomes gradually more dangerous.
var enhancement_stacks: int = 0
var max_enhancement_stacks: int = 2
var _runtime_effects: Array[Resource] = []
var _effect_trigger_counts: Dictionary = {}


func _init(mob_data: MobData) -> void:
	data = mob_data
	if data.base_stats:
		stats = CombatStats.from_data(data.base_stats)
	else:
		push_error("MobData[%s] is missing base_stats" % data.mob_name)
	_runtime_effects = _duplicate_effects(data.effects if data != null else [])


func next_action() -> MobAction:
	if data.actions.is_empty():
		return null
	var action := data.actions[action_index]
	action_index = (action_index + 1) % data.actions.size()
	return action


func get_next_action() -> MobAction:
	return next_action()


## Returns the configured echo hooks. The array is copied so callers cannot
## replace the encounter's configuration accidentally.
func get_effects() -> Array[Resource]:
	# Keep test-created/config-created effects visible if they were appended after
	# instance construction, while using private copies during real encounters.
	if _runtime_effects.is_empty() and data != null and not data.effects.is_empty():
		_runtime_effects = _duplicate_effects(data.effects)
	return _runtime_effects.duplicate()


func can_trigger_effect(effect_index: int, configured_count: int) -> bool:
	if configured_count < 0:
		return true
	return int(_effect_trigger_counts.get(effect_index, 0)) < configured_count


func record_effect_trigger(effect_index: int) -> void:
	_effect_trigger_counts[effect_index] = int(_effect_trigger_counts.get(effect_index, 0)) + 1


func get_effect_trigger_count(effect_index: int) -> int:
	return int(_effect_trigger_counts.get(effect_index, 0))


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
	copy._runtime_effects = _duplicate_effects(get_effects())
	copy._effect_trigger_counts = _effect_trigger_counts.duplicate(true)
	return copy


func take_damage(amount: int) -> int:
	return stats.take_damage(amount) if stats else 0


func is_alive() -> bool:
	return stats != null and stats.is_alive()



func _duplicate_effects(source: Array[Resource]) -> Array[Resource]:
	var copies: Array[Resource] = []
	for effect in source:
		if effect != null:
			copies.append(effect.duplicate(true))
	return copies
