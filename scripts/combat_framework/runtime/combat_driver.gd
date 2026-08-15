class_name CombatDriver
extends RefCounted

signal battle_started()
signal automatic_batch_submitted(batch: CombatEffectBatch)
signal batch_completed(result: CombatEffectBatchResult)
signal presentation_requested(result: CombatEffectBatchResult, recommended_duration: float)
signal battle_finished(snapshot: CombatStateSnapshot)

var processor: CombatEffectBatchProcessor
var flow_provider: CombatFlowProvider
var trigger_planner: CombatTriggerPlanner
var clock: CombatBattleClock

## 战斗速度影响自动结算批次之间的逻辑间隔。
var base_batch_interval: float = 0.35
var base_presentation_duration: float = 0.25
var require_presentation_acknowledgement: bool = false

var _running: bool = false
var _pending_presentation_ids: Array[String] = []
var _trigger_plans: Array[CombatEffectBatch] = []
var _last_result: CombatEffectBatchResult


func _init(
	p_processor: CombatEffectBatchProcessor = null,
	p_flow_provider: CombatFlowProvider = null,
	p_trigger_planner: CombatTriggerPlanner = null,
	p_clock: CombatBattleClock = null
) -> void:
	processor = p_processor
	flow_provider = p_flow_provider
	trigger_planner = p_trigger_planner if p_trigger_planner != null else CombatTriggerPlanner.new()
	clock = p_clock if p_clock != null else CombatBattleClock.new()
	_connect_processor()


func configure(
	p_processor: CombatEffectBatchProcessor,
	p_flow_provider: CombatFlowProvider,
	p_trigger_planner: CombatTriggerPlanner = null,
	p_clock: CombatBattleClock = null
) -> void:
	_disconnect_processor()
	processor = p_processor
	flow_provider = p_flow_provider
	if p_trigger_planner != null:
		trigger_planner = p_trigger_planner
	if p_clock != null:
		clock = p_clock
	_connect_processor()


func start() -> void:
	if processor == null or flow_provider == null:
		push_error("CombatDriver 需要 EffectBatchProcessor 和 CombatFlowProvider")
		return
	_running = true
	_pending_presentation_ids.clear()
	_trigger_plans.clear()
	_last_result = null
	flow_provider.start(processor.create_snapshot())
	clock.schedule(0.0)
	battle_started.emit()


func stop() -> void:
	_running = false
	_trigger_plans.clear()


func is_running() -> bool:
	return _running


func set_battle_speed(value: float) -> void:
	clock.set_battle_speed(value)


func get_battle_speed() -> float:
	return clock.battle_speed


## 每帧推进一次。玩家操作批次已经直接进入处理器，所以它们优先于驱动的后续计划。
func advance(real_delta: float) -> void:
	if not _running or processor == null:
		return
	clock.advance(real_delta)

	# 当前批次不可中断；一旦到达批次边界，处理器中已有的玩家操作或系统批次先执行。
	if not processor.is_processing() and processor.has_pending_batches():
		processor.process_next()
		return

	# 表现确认只阻止自动流程，不阻止玩家把操作批次直接塞入处理器。
	if not _pending_presentation_ids.is_empty():
		return
	if not clock.is_ready():
		return

	var next_batch := _take_next_automatic_batch()
	if next_batch != null:
		processor.enqueue(next_batch)
		automatic_batch_submitted.emit(next_batch)
		processor.process_next()
		return

	var snapshot := processor.create_snapshot()
	if flow_provider.is_finished(snapshot):
		_running = false
		battle_finished.emit(snapshot)


func acknowledge_presentation(batch_id: String) -> void:
	var index := _pending_presentation_ids.find(batch_id)
	if index >= 0:
		_pending_presentation_ids.remove_at(index)


func is_waiting_for_presentation() -> bool:
	return not _pending_presentation_ids.is_empty()


func has_planned_triggers() -> bool:
	return not _trigger_plans.is_empty()


func _take_next_automatic_batch() -> CombatEffectBatch:
	if not _trigger_plans.is_empty():
		return _trigger_plans.pop_front()
	return flow_provider.build_next_batch(processor.create_snapshot(), _last_result)


func _on_batch_finished(result: CombatEffectBatchResult) -> void:
	_last_result = result
	var snapshot := processor.create_snapshot()
	flow_provider.on_batch_finished(result, snapshot)
	if result.is_committed():
		var planned := trigger_planner.plan(result.events, snapshot)
		for batch in planned:
			_trigger_plans.append(batch)
	clock.schedule(base_batch_interval)
	batch_completed.emit(result)
	if require_presentation_acknowledgement and result.is_committed():
		_pending_presentation_ids.append(result.batch_id)
		presentation_requested.emit(result, clock.scale_duration(base_presentation_duration))


func _connect_processor() -> void:
	if processor == null:
		return
	if not processor.batch_finished.is_connected(_on_batch_finished):
		processor.batch_finished.connect(_on_batch_finished)


func _disconnect_processor() -> void:
	if processor == null:
		return
	if processor.batch_finished.is_connected(_on_batch_finished):
		processor.batch_finished.disconnect(_on_batch_finished)

