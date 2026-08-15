class_name CombatGainGoldEffectHandler
extends CombatEffectHandler


func _init() -> void:
	super(&"gain_gold")


func validate(effect: CombatBatchEffect, snapshot: CombatStateSnapshot) -> CombatValidationResult:
	if not effect.parameters.has("amount"):
		return CombatValidationResult.rejected(&"missing_gold_amount", "金币增加效果缺少 amount")
	if int(effect.get_parameter("amount", 0)) < 0:
		return CombatValidationResult.rejected(&"negative_gold_gain", "金币增加不能为负数")
	var player_id := str(snapshot.get_value(["player", "entity_id"], "player"))
	if effect.target_entity_ids.size() != 1 or effect.target_entity_ids[0] != player_id:
		return CombatValidationResult.rejected(&"gold_target_must_be_player", "金币效果只能作用于当前玩家")
	return CombatValidationResult.accepted()


func apply(effect: CombatBatchEffect, writer: CombatStateWriter) -> CombatValidationResult:
	var amount := maxi(int(effect.get_parameter("amount", 0)), 0)
	var before := maxi(int(writer.get_value(["player", "gold"], 0)), 0)
	if amount > 0:
		writer.set_value(["player", "gold"], before + amount, CombatEventTypes.GOLD_CHANGED, effect.source_entity_id, {
			"delta": amount,
		})
	return CombatValidationResult.accepted()
