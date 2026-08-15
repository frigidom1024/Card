class_name CombatBattleSession
extends RefCounted

const FlowScript = preload("res://scripts/combat_framework/runtime/combat_linear_chain_flow_provider.gd")
const BattleOutcomeScript = preload("res://scripts/combat_framework/protocol/combat_battle_outcome.gd")

signal battle_started()
signal automatic_batch_submitted(batch: CombatEffectBatch)
signal batch_completed(result: CombatEffectBatchResult)
signal state_events_emitted(events: Array[CombatStateEvent])
signal presentation_requested(result: CombatEffectBatchResult, recommended_duration: float)
signal battle_finished(outcome: StringName, snapshot: CombatStateSnapshot)

var processor: CombatEffectBatchProcessor
var flow_provider: CombatFlowProvider
var driver: CombatDriver


func _init(
	initial_data: Dictionary = {},
	initial_phase: StringName = &"combat"
) -> void:
	processor = CombatStandardEffectLibrary.create_processor(initial_data, initial_phase)
	flow_provider = FlowScript.new()
	driver = CombatDriver.new(processor, flow_provider)
	_connect_components()


func start() -> void:
	driver.start()


func advance(real_delta: float) -> void:
	driver.advance(real_delta)


func set_battle_speed(speed: float) -> void:
	driver.set_battle_speed(speed)


func submit_player_operation(batch: CombatEffectBatch) -> bool:
	if batch == null:
		return false
	if batch.batch_type != CombatEffectBatch.Type.PLAYER_OPERATION:
		return false
	if get_outcome() != BattleOutcomeScript.RUNNING:
		return false
	processor.enqueue(batch)
	return true


func acknowledge_presentation(batch_id: String) -> void:
	driver.acknowledge_presentation(batch_id)


func create_snapshot() -> CombatStateSnapshot:
	return processor.create_snapshot()


func get_outcome() -> StringName:
	return flow_provider.get_outcome(processor.create_snapshot())


func _connect_components() -> void:
	driver.battle_started.connect(_on_battle_started)
	driver.automatic_batch_submitted.connect(_on_automatic_batch_submitted)
	driver.batch_completed.connect(_on_batch_completed)
	driver.presentation_requested.connect(_on_presentation_requested)
	driver.battle_finished.connect(_on_driver_battle_finished)
	processor.state_events_emitted.connect(_on_state_events_emitted)


func _on_battle_started() -> void:
	battle_started.emit()


func _on_automatic_batch_submitted(batch: CombatEffectBatch) -> void:
	automatic_batch_submitted.emit(batch)


func _on_batch_completed(result: CombatEffectBatchResult) -> void:
	batch_completed.emit(result)


func _on_state_events_emitted(events: Array[CombatStateEvent]) -> void:
	state_events_emitted.emit(events)


func _on_presentation_requested(
	result: CombatEffectBatchResult,
	recommended_duration: float
) -> void:
	presentation_requested.emit(result, recommended_duration)


func _on_driver_battle_finished(snapshot: CombatStateSnapshot) -> void:
	battle_finished.emit(flow_provider.get_outcome(snapshot), snapshot)
