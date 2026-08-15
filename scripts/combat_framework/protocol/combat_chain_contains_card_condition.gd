class_name CombatChainContainsCardCondition
extends CombatBatchCondition

var card_id: String = ""


func _init(p_card_id: String = "") -> void:
	card_id = p_card_id


func validate(snapshot: CombatStateSnapshot) -> CombatValidationResult:
	var chain_ids: Array = snapshot.get_value(["chain", "card_ids"], []) as Array
	if card_id.is_empty() or chain_ids.find(card_id) < 0:
		return CombatValidationResult.rejected(&"target_not_in_chain", "操作目标已经不在当前牌链中")
	return CombatValidationResult.accepted()
