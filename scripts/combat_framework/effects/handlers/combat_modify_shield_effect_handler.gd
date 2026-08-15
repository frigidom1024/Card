class_name CombatModifyShieldEffectHandler
extends "res://scripts/combat_framework/effects/handlers/combat_target_effect_handler.gd"


func _init() -> void:
	super(&"modify_shield")


func validate(effect: CombatBatchEffect, snapshot: CombatStateSnapshot) -> CombatValidationResult:
	if effect.target_entity_ids.size() != 1:
		return CombatValidationResult.rejected(&"shield_requires_one_target", "护盾修改效果必须具有一个目标")
	if not effect.parameters.has("amount"):
		return CombatValidationResult.rejected(&"missing_shield_amount", "护盾修改效果缺少 amount")
	if _resolve_target(effect, snapshot).is_empty():
		return CombatValidationResult.rejected(&"unknown_shield_target", "护盾目标不存在")
	return CombatValidationResult.accepted()


func apply(effect: CombatBatchEffect, writer: CombatStateWriter) -> CombatValidationResult:
	var target := _resolve_target(effect, writer)
	if target.is_empty():
		return CombatValidationResult.rejected(&"unknown_shield_target", "护盾目标不存在")
	var path: Array = target["path"]
	path.append("shield")
	var before := maxi(int(writer.get_value(path, 0)), 0)
	var after := maxi(before + int(effect.get_parameter("amount", 0)), 0)
	if after != before:
		writer.set_value(path, after, CombatEventTypes.SHIELD_CHANGED, effect.source_entity_id, {
			"delta": after - before,
		})
	return CombatValidationResult.accepted()
