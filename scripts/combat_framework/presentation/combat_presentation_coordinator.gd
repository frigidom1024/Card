class_name CombatPresentationCoordinator
extends RefCounted

var _session: CombatBattleSession
var _builder: CombatEffectPresentationPlanBuilder
var _scheduler: CombatEffectPresentationScheduler
var _barriers: Dictionary = {}
var _configured: bool = false


func configure(
	session: CombatBattleSession,
	builder: CombatEffectPresentationPlanBuilder,
	scheduler: CombatEffectPresentationScheduler
) -> void:
	if session == null or builder == null or scheduler == null:
		push_error("CombatPresentationCoordinator 需要 Session、Builder 和 Scheduler")
		return
	if _configured:
		shutdown()
	_session = session
	_builder = builder
	_scheduler = scheduler
	_session.presentation_requested.connect(_on_presentation_requested)
	_session.battle_speed_changed.connect(_on_battle_speed_changed)
	_scheduler.effect_plan_finished.connect(_on_effect_plan_finished)
	_scheduler.set_battle_speed(_session.get_battle_speed())
	_configured = true


func shutdown() -> void:
	if not _configured:
		return
	_disconnect_session_signals()
	_scheduler.cancel_all()

	var remaining_barriers := _barriers.values().duplicate()
	for barrier_value in remaining_barriers:
		var barrier: CombatBatchPresentationBarrier = barrier_value
		if barrier != null:
			barrier.cancel_and_complete()
	_barriers.clear()

	if _scheduler.effect_plan_finished.is_connected(_on_effect_plan_finished):
		_scheduler.effect_plan_finished.disconnect(_on_effect_plan_finished)
	_session = null
	_builder = null
	_scheduler = null
	_configured = false


func get_pending_batch_ids() -> Array[String]:
	var batch_ids: Array[String] = []
	for batch_id in _barriers.keys():
		batch_ids.append(str(batch_id))
	batch_ids.sort()
	return batch_ids


func _on_presentation_requested(
	result: CombatEffectBatchResult,
	recommended_duration: float
) -> void:
	if not _configured or result == null:
		return
	var plans := _builder.build_effect_plans(
		result,
		recommended_duration,
		_session.get_battle_speed()
	)
	var effect_keys: Array[String] = []
	for plan in plans:
		effect_keys.append(plan.effect_key)

	var barrier := CombatBatchPresentationBarrier.new()
	barrier.configure(result.batch_id, effect_keys)
	barrier.completed.connect(_on_batch_barrier_completed, CONNECT_ONE_SHOT)
	_barriers[result.batch_id] = barrier

	if plans.is_empty():
		barrier.complete_empty_deferred()
		return
	for plan in plans:
		_scheduler.enqueue_effect_plan(plan)


func _on_effect_plan_finished(
	batch_id: String,
	_effect_id: String,
	effect_key: String
) -> void:
	var barrier: CombatBatchPresentationBarrier = _barriers.get(batch_id)
	if barrier != null:
		barrier.mark_effect_finished(effect_key)


func _on_batch_barrier_completed(batch_id: String) -> void:
	if not _barriers.has(batch_id):
		return
	_barriers.erase(batch_id)
	if _session != null:
		_session.acknowledge_presentation(batch_id)


func _on_battle_speed_changed(speed: float) -> void:
	if _scheduler != null:
		_scheduler.set_battle_speed(speed)


func _disconnect_session_signals() -> void:
	if _session == null:
		return
	if _session.presentation_requested.is_connected(_on_presentation_requested):
		_session.presentation_requested.disconnect(_on_presentation_requested)
	if _session.battle_speed_changed.is_connected(_on_battle_speed_changed):
		_session.battle_speed_changed.disconnect(_on_battle_speed_changed)
