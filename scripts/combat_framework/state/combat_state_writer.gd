class_name CombatStateWriter
extends RefCounted

## EffectHandler 只能通过本对象修改批次草稿；正式状态由处理器最终原子提交。
var _draft: CombatStateDraft
var _batch: CombatEffectBatch
var _current_effect: CombatBatchEffect


func _init(draft: CombatStateDraft, batch: CombatEffectBatch) -> void:
	_draft = draft
	_batch = batch


func set_current_effect(effect: CombatBatchEffect) -> void:
	_current_effect = effect


func get_value(path: Array, default_value: Variant = null) -> Variant:
	return _draft.create_snapshot().get_value(path, default_value)


func set_value(
	path: Array,
	value: Variant,
	event_type: StringName = CombatEventTypes.STATE_VALUE_CHANGED,
	entity_id: String = "",
	extra_payload: Dictionary = {}
) -> void:
	if path.is_empty():
		return
	var before: Variant = get_value(path)
	_set_nested_value(_draft.data, path, value)
	_draft.changed = true
	var payload := extra_payload.duplicate(true)
	payload["path"] = path.duplicate()
	payload["before"] = before
	payload["after"] = value
	emit_event(event_type, entity_id, payload)


func increment_value(
	path: Array,
	amount: int,
	event_type: StringName = CombatEventTypes.STATE_VALUE_CHANGED,
	entity_id: String = "",
	extra_payload: Dictionary = {}
) -> int:
	var next_value := int(get_value(path, 0)) + amount
	set_value(path, next_value, event_type, entity_id, extra_payload)
	return next_value


func mark_chain_changed(extra_payload: Dictionary = {}) -> void:
	if not _draft.chain_changed:
		_draft.chain_revision += 1
	_draft.chain_changed = true
	_draft.changed = true
	emit_event(CombatEventTypes.CHAIN_CHANGED, "", extra_payload)


func set_phase(next_phase: StringName) -> void:
	if _draft.phase == next_phase:
		return
	var previous := _draft.phase
	_draft.phase = next_phase
	_draft.changed = true
	emit_event(CombatEventTypes.PHASE_CHANGED, "", {
		"before": previous,
		"after": next_phase,
	})


func emit_event(
	event_type: StringName,
	entity_id: String = "",
	payload: Dictionary = {},
	target_entity_ids: Array[String] = []
) -> CombatStateEvent:
	var event := CombatStateEvent.new(event_type, payload)
	event.batch_id = _batch.batch_id
	event.cause_event_id = _batch.cause_event_id
	event.source_entity_id = entity_id if not entity_id.is_empty() else _batch.source_entity_id
	if _current_effect != null:
		event.effect_id = _current_effect.effect_id
		if event.source_entity_id.is_empty():
			event.source_entity_id = _current_effect.source_entity_id
		event.target_entity_ids = (
			target_entity_ids.duplicate()
			if not target_entity_ids.is_empty()
			else _current_effect.target_entity_ids.duplicate()
		)
	else:
		event.target_entity_ids = target_entity_ids.duplicate()
	event.sequence = _draft.events.size()
	event.event_id = "%s:%d" % [_batch.batch_id, event.sequence]
	_draft.events.append(event)
	return event


static func _set_nested_value(root: Dictionary, path: Array, value: Variant) -> void:
	var cursor := root
	for index in range(path.size() - 1):
		var key: Variant = path[index]
		var next_value: Variant = cursor.get(key)
		if not next_value is Dictionary:
			next_value = {}
			cursor[key] = next_value
		cursor = next_value as Dictionary
	cursor[path.back()] = value

