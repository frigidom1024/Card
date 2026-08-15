class_name CombatBatchFactory
extends RefCounted

## 玩家攻击批次和怪物攻击批次故意使用不同工厂入口和生命周期协议。
static func create_battle_start(
	batch_id: String,
	effects: Array[CombatBatchEffect] = []
) -> CombatEffectBatch:
	var batch := _create_flow_batch(batch_id, CombatEffectBatch.Type.BATTLE_START, "battle", effects)
	batch.started_event_type = CombatEventTypes.BATTLE_STARTED
	batch.finished_event_type = CombatEventTypes.BATCH_FINISHED
	return batch


static func create_battle_end(
	batch_id: String,
	effects: Array[CombatBatchEffect] = []
) -> CombatEffectBatch:
	var batch := _create_flow_batch(batch_id, CombatEffectBatch.Type.BATTLE_END, "battle", effects)
	batch.started_event_type = CombatEventTypes.BATCH_STARTED
	batch.finished_event_type = CombatEventTypes.BATTLE_FINISHED
	return batch


static func create_player_attack(
	batch_id: String,
	source_card_id: String,
	effects: Array[CombatBatchEffect]
) -> CombatEffectBatch:
	var batch := _create_flow_batch(batch_id, CombatEffectBatch.Type.PLAYER_ATTACK, source_card_id, effects)
	batch.started_event_type = CombatEventTypes.PLAYER_ATTACK_STARTED
	batch.finished_event_type = CombatEventTypes.PLAYER_ATTACK_FINISHED
	return batch


static func create_monster_attack(
	batch_id: String,
	source_monster_id: String,
	effects: Array[CombatBatchEffect]
) -> CombatEffectBatch:
	var batch := _create_flow_batch(batch_id, CombatEffectBatch.Type.MONSTER_ATTACK, source_monster_id, effects)
	batch.started_event_type = CombatEventTypes.MONSTER_ATTACK_STARTED
	batch.finished_event_type = CombatEventTypes.MONSTER_ATTACK_FINISHED
	return batch


static func create_card_trigger(
	batch_id: String,
	source_card_id: String,
	cause_event_id: String,
	effects: Array[CombatBatchEffect]
) -> CombatEffectBatch:
	var batch := _create_flow_batch(batch_id, CombatEffectBatch.Type.CARD_TRIGGER, source_card_id, effects)
	batch.source_type = CombatEffectBatch.SourceType.CARD_TRIGGER
	batch.priority = CombatEffectBatch.Priority.CARD_TRIGGER
	batch.cause_event_id = cause_event_id
	batch.started_event_type = CombatEventTypes.CARD_TRIGGER_STARTED
	batch.finished_event_type = CombatEventTypes.CARD_TRIGGER_FINISHED
	for effect in effects:
		if effect == null:
			continue
		effect.add_tag(CombatEffectTags.PRESENTATION_CARD_TRIGGER)
		break
	return batch


static func create_player_operation(
	batch_id: String,
	operation_card_id: String,
	effects: Array[CombatBatchEffect]
) -> CombatEffectBatch:
	var batch := CombatEffectBatch.new(batch_id)
	batch.batch_type = CombatEffectBatch.Type.PLAYER_OPERATION
	batch.source_type = CombatEffectBatch.SourceType.PLAYER_OPERATION
	batch.source_entity_id = operation_card_id
	batch.priority = CombatEffectBatch.Priority.PLAYER_OPERATION
	batch.started_event_type = CombatEventTypes.PLAYER_OPERATION_STARTED
	batch.finished_event_type = CombatEventTypes.PLAYER_OPERATION_FINISHED
	batch.effects = effects.duplicate()
	return batch


static func _create_flow_batch(
	batch_id: String,
	batch_type: CombatEffectBatch.Type,
	source_entity_id: String,
	effects: Array[CombatBatchEffect]
) -> CombatEffectBatch:
	var batch := CombatEffectBatch.new(batch_id)
	batch.batch_type = batch_type
	batch.source_type = CombatEffectBatch.SourceType.BATTLE_DRIVER
	batch.source_entity_id = source_entity_id
	batch.priority = CombatEffectBatch.Priority.BATTLE_FLOW
	batch.effects = effects.duplicate()
	return batch
