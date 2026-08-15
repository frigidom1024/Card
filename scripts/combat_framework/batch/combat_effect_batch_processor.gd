class_name CombatEffectBatchProcessor
extends RefCounted

signal batch_started(batch: CombatEffectBatch)
signal state_events_emitted(events: Array[CombatStateEvent])
signal batch_finished(result: CombatEffectBatchResult)

var _state: CombatRuntimeState
var _registry: CombatEffectHandlerRegistry
var _queue := CombatEffectBatchQueue.new()
var _state_rules: Array[CombatStateRule] = []
var _processing: bool = false


func _init(
	p_state: CombatRuntimeState = null,
	p_registry: CombatEffectHandlerRegistry = null
) -> void:
	_state = p_state if p_state != null else CombatRuntimeState.new()
	_registry = p_registry if p_registry != null else CombatEffectHandlerRegistry.new()


func enqueue(batch: CombatEffectBatch) -> void:
	_queue.enqueue(batch)


func add_state_rule(rule: CombatStateRule) -> void:
	if rule != null:
		_state_rules.append(rule)


func is_processing() -> bool:
	return _processing


func has_pending_batches() -> bool:
	return not _queue.is_empty()


func pending_batch_count() -> int:
	return _queue.size()


func create_snapshot() -> CombatStateSnapshot:
	return _state.create_snapshot()


func process_next() -> CombatEffectBatchResult:
	if _processing:
		return _create_result(null, CombatEffectBatchResult.Status.FAILED, &"processor_busy", "批次处理器正在执行其他批次")
	var batch := _queue.pop_next()
	if batch == null:
		return null
	_processing = true
	batch_started.emit(batch)
	var result := _execute_batch(batch)
	_processing = false
	if not result.events.is_empty():
		state_events_emitted.emit(result.events)
	batch_finished.emit(result)
	return result


func process_all(max_batches: int = 1024) -> Array[CombatEffectBatchResult]:
	var results: Array[CombatEffectBatchResult] = []
	while has_pending_batches() and results.size() < max_batches:
		var result := process_next()
		if result != null:
			results.append(result)
	return results


func _execute_batch(batch: CombatEffectBatch) -> CombatEffectBatchResult:
	var snapshot := _state.create_snapshot()
	var validation := _validate_batch(batch, snapshot)
	if not validation.valid:
		return _create_rejected_result(batch, CombatEffectBatchResult.Status.CANCELED, validation)

	var draft := _state._begin_draft()
	var writer := CombatStateWriter.new(draft, batch)
	writer.emit_event(batch.started_event_type, batch.source_entity_id, {
		"batch_type": batch.batch_type,
		"source_type": batch.source_type,
	})

	for effect in batch.effects:
		if effect == null:
			continue
		if effect.effect_id.is_empty():
			return _create_rejected_result(
				batch,
				CombatEffectBatchResult.Status.FAILED,
				CombatValidationResult.rejected(&"missing_effect_id", "批次内效果必须具有稳定 ID")
			)
		var handler := _registry.get_handler(effect.effect_type)
		if handler == null:
			return _create_rejected_result(
				batch,
				CombatEffectBatchResult.Status.FAILED,
				CombatValidationResult.rejected(&"missing_effect_handler", "没有注册效果处理器：%s" % effect.effect_type)
			)
		var effect_validation := handler.validate(effect, draft.create_snapshot())
		if not effect_validation.valid:
			return _create_rejected_result(batch, CombatEffectBatchResult.Status.CANCELED, effect_validation)
		writer.set_current_effect(effect)
		var apply_result := handler.apply(effect, writer)
		if not apply_result.valid:
			return _create_rejected_result(batch, CombatEffectBatchResult.Status.FAILED, apply_result)
		writer.emit_event(CombatEventTypes.EFFECT_APPLIED, effect.source_entity_id, {
			"effect_type": effect.effect_type,
		}, effect.target_entity_ids)
		for rule in _state_rules:
			var rule_result := rule.evaluate(effect, writer)
			if not rule_result.valid:
				return _create_rejected_result(batch, CombatEffectBatchResult.Status.FAILED, rule_result)

	writer.set_current_effect(null)
	writer.emit_event(batch.finished_event_type, batch.source_entity_id, {
		"batch_type": batch.batch_type,
		"source_type": batch.source_type,
	})
	var committed_snapshot := _state._commit_draft(draft)
	for event in draft.events:
		event.state_revision = committed_snapshot.state_revision
		event.chain_revision = committed_snapshot.chain_revision
	var result := _create_result(batch, CombatEffectBatchResult.Status.COMMITTED)
	result.state_revision = committed_snapshot.state_revision
	result.chain_revision = committed_snapshot.chain_revision
	result.events = draft.events.duplicate()
	return result


func _validate_batch(
	batch: CombatEffectBatch,
	snapshot: CombatStateSnapshot
) -> CombatValidationResult:
	if batch.batch_id.is_empty():
		return CombatValidationResult.rejected(&"missing_batch_id", "效果批次必须具有稳定 ID")
	if not batch.atomic:
		return CombatValidationResult.rejected(&"non_atomic_batch_unsupported", "当前战斗框架只允许原子效果批次")
	if batch.expected_state_revision >= 0 and batch.expected_state_revision != snapshot.state_revision:
		return CombatValidationResult.rejected(&"stale_state_revision", "战斗状态版本已经变化")
	if batch.expected_chain_revision >= 0 and batch.expected_chain_revision != snapshot.chain_revision:
		return CombatValidationResult.rejected(&"stale_chain_revision", "牌链版本已经变化")
	for condition in batch.conditions:
		var condition_result := condition.validate(snapshot)
		if not condition_result.valid:
			return condition_result
	return CombatValidationResult.accepted()


func _create_rejected_result(
	batch: CombatEffectBatch,
	status: CombatEffectBatchResult.Status,
	validation: CombatValidationResult
) -> CombatEffectBatchResult:
	var result := _create_result(batch, status, validation.reason_code, validation.message)
	var event_type := CombatEventTypes.BATCH_CANCELED if status == CombatEffectBatchResult.Status.CANCELED else CombatEventTypes.BATCH_FAILED
	var event := CombatStateEvent.new(event_type, {
		"reason_code": validation.reason_code,
		"message": validation.message,
	})
	event.event_id = "%s:rejected" % batch.batch_id
	event.batch_id = batch.batch_id
	event.source_entity_id = batch.source_entity_id
	event.state_revision = _state.create_snapshot().state_revision
	event.chain_revision = _state.create_snapshot().chain_revision
	result.events.append(event)
	return result


func _create_result(
	batch: CombatEffectBatch,
	status: CombatEffectBatchResult.Status,
	reason_code: StringName = &"",
	message: String = ""
) -> CombatEffectBatchResult:
	var result := CombatEffectBatchResult.new()
	result.status = status
	if batch != null:
		result.batch_id = batch.batch_id
		result.batch_type = batch.batch_type
		result.source_type = batch.source_type
	var snapshot := _state.create_snapshot()
	result.state_revision = snapshot.state_revision
	result.chain_revision = snapshot.chain_revision
	result.reason_code = reason_code
	result.message = message
	return result
