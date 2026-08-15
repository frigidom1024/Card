class_name CombatSplitChainEffectHandler
extends CombatEffectHandler


func _init() -> void:
	super(&"split_chain")


func validate(effect: CombatBatchEffect, snapshot: CombatStateSnapshot) -> CombatValidationResult:
	if effect.target_entity_ids.size() != 1:
		return CombatValidationResult.rejected(&"split_chain_requires_one_target", "拆链效果必须具有一个目标卡牌")
	var chain_ids: Array = snapshot.get_value(["chain", "card_ids"], []) as Array
	if chain_ids.find(effect.target_entity_ids[0]) < 0:
		return CombatValidationResult.rejected(&"target_not_in_chain", "拆链目标已经不在当前牌链中")
	return CombatValidationResult.accepted()


func apply(effect: CombatBatchEffect, writer: CombatStateWriter) -> CombatValidationResult:
	var chain_before: Array = writer.get_value(["chain", "card_ids"], []) as Array
	var target_id := effect.target_entity_ids[0]
	var target_index := chain_before.find(target_id)
	if target_index < 0:
		return CombatValidationResult.rejected(&"target_not_in_chain", "拆链目标已经不在当前牌链中")
	var include_target := bool(effect.get_parameter("include_target_in_active_chain", false))
	var split_index := target_index + 1 if include_target else target_index
	var active_ids := chain_before.slice(0, split_index)
	var detached_ids := chain_before.slice(split_index)
	writer.set_value(["chain", "card_ids"], active_ids)
	writer.set_value(["chain", "detached_card_ids"], detached_ids)
	writer.mark_chain_changed({
		"target_card_id": target_id,
		"target_index_before": target_index,
	})
	writer.emit_event(CombatEventTypes.CHAIN_SPLIT, effect.source_entity_id, {
		"target_card_id": target_id,
		"target_index_before": target_index,
		"active_card_ids": active_ids.duplicate(),
		"detached_card_ids": detached_ids.duplicate(),
		"include_target_in_active_chain": include_target,
	}, [target_id])
	return CombatValidationResult.accepted()
