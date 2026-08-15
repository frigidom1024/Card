class_name CombatModifyCardPointsEffectHandler
extends "res://scripts/combatv2/effects/handlers/combat_target_effect_handler.gd"


func _init() -> void:
	super(&"modify_card_points")


func validate(effect: CombatBatchEffect, snapshot: CombatStateSnapshot) -> CombatValidationResult:
	if effect.target_entity_ids.size() != 1:
		return CombatValidationResult.rejected(&"card_points_requires_one_target", "卡牌点数修改效果必须具有一个目标")
	if not effect.parameters.has("amount"):
		return CombatValidationResult.rejected(&"missing_card_points_amount", "卡牌点数修改效果缺少 amount")
	var target := _resolve_target(effect, snapshot)
	if target.is_empty() or target.get("kind") != &"card":
		return CombatValidationResult.rejected(&"card_points_target_must_be_card", "卡牌点数效果只能作用于卡牌")
	return CombatValidationResult.accepted()


func apply(effect: CombatBatchEffect, writer: CombatStateWriter) -> CombatValidationResult:
	var target := _resolve_target(effect, writer)
	if target.is_empty() or target.get("kind") != &"card":
		return CombatValidationResult.rejected(&"card_points_target_must_be_card", "卡牌点数效果只能作用于卡牌")
	var path: Array = target["path"]
	path.append("points")
	var before := maxi(int(writer.get_value(path, 0)), 0)
	var after := maxi(before + int(effect.get_parameter("amount", 0)), 0)
	if after != before:
		writer.set_value(path, after, CombatEventTypes.CARD_POINTS_CHANGED, effect.source_entity_id, {
			"delta": after - before,
		})
	return CombatValidationResult.accepted()
