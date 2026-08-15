class_name CombatTriggerPlanner
extends RefCounted

var _rules: Array[CombatTriggerRule] = []
var _next_registration_sequence: int = 0


func register(rule: CombatTriggerRule) -> void:
	if rule == null:
		return
	rule.registration_sequence = _next_registration_sequence
	_next_registration_sequence += 1
	_rules.append(rule)


func plan(
	events: Array[CombatStateEvent],
	snapshot: CombatStateSnapshot
) -> Array[CombatEffectBatch]:
	var batches: Array[CombatEffectBatch] = []
	var ordered_rules: Array[CombatTriggerRule] = _rules.duplicate()
	ordered_rules.sort_custom(_sort_rules)
	for event in events:
		for rule in ordered_rules:
			if not rule.matches(event, snapshot):
				continue
			var batch: CombatEffectBatch = rule.create_batch(event, snapshot)
			if batch != null:
				batches.append(batch)
	return batches


static func _sort_rules(left: CombatTriggerRule, right: CombatTriggerRule) -> bool:
	if left.priority != right.priority:
		return left.priority > right.priority
	return left.registration_sequence < right.registration_sequence

