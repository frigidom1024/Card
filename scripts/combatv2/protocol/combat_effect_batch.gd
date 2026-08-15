class_name CombatEffectBatch
extends RefCounted

enum Type {
	BATTLE_START,
	BATTLE_END,
	PLAYER_ATTACK,
	MONSTER_ATTACK,
	CARD_TRIGGER,
	PLAYER_OPERATION,
	FLOW_TRANSITION,
	SYSTEM_RULE,
}

enum SourceType {
	BATTLE_DRIVER,
	CARD_TRIGGER,
	PLAYER_OPERATION,
	SYSTEM_RULE,
}

enum Priority {
	BATTLE_FLOW = 100,
	CARD_TRIGGER = 200,
	PLAYER_OPERATION = 300,
	SYSTEM_RULE = 400,
}

var batch_id: String = ""
var batch_type: Type = Type.FLOW_TRANSITION
var source_type: SourceType = SourceType.BATTLE_DRIVER
var source_entity_id: String = ""
var cause_event_id: String = ""
var priority: int = Priority.BATTLE_FLOW
var enqueue_sequence: int = -1

## -1 表示不锁定版本；非负值会在执行前与最新状态重新核对。
var expected_state_revision: int = -1
var expected_chain_revision: int = -1
var atomic: bool = true
var conditions: Array[CombatBatchCondition] = []
var effects: Array[CombatBatchEffect] = []
var metadata: Dictionary = {}

## 不同批次可以声明不同生命周期事件，玩家攻击与怪物攻击因此完全分离。
var started_event_type: StringName = CombatEventTypes.BATCH_STARTED
var finished_event_type: StringName = CombatEventTypes.BATCH_FINISHED


func _init(p_batch_id: String = "") -> void:
	batch_id = p_batch_id


func add_effect(effect: CombatBatchEffect) -> CombatEffectBatch:
	if effect != null:
		effects.append(effect)
	return self


func add_condition(condition: CombatBatchCondition) -> CombatEffectBatch:
	if condition != null:
		conditions.append(condition)
	return self


func set_metadata(key: Variant, value: Variant) -> CombatEffectBatch:
	metadata[key] = value
	return self
