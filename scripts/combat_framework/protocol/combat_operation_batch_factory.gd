class_name CombatOperationBatchFactory
extends RefCounted

const ChainContainsCardConditionScript = preload("res://scripts/combat_framework/protocol/combat_chain_contains_card_condition.gd")

## 操作预览只需要读取 metadata.target_card_id，不在协议层预测结算结果。
static func create_retreat_batch(
	batch_id: String,
	operation_card_id: String,
	target_card_id: String,
	expected_chain_revision: int
) -> CombatEffectBatch:
	var split_effect := CombatBatchEffect.new(
		&"split_chain",
		"%s:split_chain" % batch_id,
		operation_card_id,
		[target_card_id],
		{"include_target_in_active_chain": false}
	)
	var batch := CombatBatchFactory.create_player_operation(batch_id, operation_card_id, [split_effect])
	batch.expected_chain_revision = expected_chain_revision
	batch.add_condition(ChainContainsCardConditionScript.new(target_card_id))
	batch.set_metadata("operation_type", &"retreat")
	batch.set_metadata("target_card_id", target_card_id)
	batch.set_metadata("preview_mode", &"target_only")
	return batch


static func create_gold_shield_batch(
	batch_id: String,
	operation_card_id: String,
	target_card_id: String,
	gold_cost: int,
	shield_amount: int,
	expected_chain_revision: int,
	player_entity_id: String = "player"
) -> CombatEffectBatch:
	var spend_effect := CombatBatchEffect.new(
		&"spend_gold",
		"%s:spend_gold" % batch_id,
		operation_card_id,
		[player_entity_id],
		{"amount": gold_cost}
	)
	var shield_effect := CombatBatchEffect.new(
		&"modify_shield",
		"%s:modify_shield" % batch_id,
		operation_card_id,
		[target_card_id],
		{"amount": shield_amount}
	)
	var batch := CombatBatchFactory.create_player_operation(
		batch_id,
		operation_card_id,
		[spend_effect, shield_effect]
	)
	batch.expected_chain_revision = expected_chain_revision
	batch.add_condition(ChainContainsCardConditionScript.new(target_card_id))
	batch.set_metadata("operation_type", &"gold_shield")
	batch.set_metadata("target_card_id", target_card_id)
	batch.set_metadata("preview_mode", &"target_only")
	return batch
