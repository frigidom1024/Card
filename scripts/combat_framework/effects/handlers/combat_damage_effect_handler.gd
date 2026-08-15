class_name CombatDamageEffectHandler
extends "res://scripts/combat_framework/effects/handlers/combat_target_effect_handler.gd"


func _init() -> void:
	super(&"damage")


func validate(effect: CombatBatchEffect, snapshot: CombatStateSnapshot) -> CombatValidationResult:
	if effect.target_entity_ids.size() != 1:
		return CombatValidationResult.rejected(&"damage_requires_one_target", "伤害效果必须具有一个目标")
	if not effect.parameters.has("amount"):
		return CombatValidationResult.rejected(&"missing_damage_amount", "伤害效果缺少 amount")
	if int(effect.get_parameter("amount", 0)) < 0:
		return CombatValidationResult.rejected(&"negative_damage", "伤害值不能为负数")
	if _resolve_target(effect, snapshot).is_empty():
		return CombatValidationResult.rejected(&"unknown_damage_target", "伤害目标不存在")
	return CombatValidationResult.accepted()


func apply(effect: CombatBatchEffect, writer: CombatStateWriter) -> CombatValidationResult:
	var target := _resolve_target(effect, writer)
	if target.is_empty():
		return CombatValidationResult.rejected(&"unknown_damage_target", "伤害目标不存在")
	var base_path: Array = target["path"]
	var entity_id := str(target["entity_id"])
	var vitality_key := str(target["vitality_key"])
	var incoming := maxi(int(effect.get_parameter("amount", 0)), 0)
	var shield_path := base_path + ["shield"]
	var vitality_path := base_path + [vitality_key]
	var shield_before := maxi(int(writer.get_value(shield_path, 0)), 0)
	var vitality_before := maxi(int(writer.get_value(vitality_path, 0)), 0)
	var absorbed := mini(shield_before, incoming)
	var applied := mini(vitality_before, incoming - absorbed)
	var shield_after := shield_before - absorbed
	var vitality_after := vitality_before - applied
	if shield_after != shield_before:
		writer.set_value(shield_path, shield_after, CombatEventTypes.SHIELD_CHANGED, effect.source_entity_id, {
			"delta": shield_after - shield_before,
		})
	if vitality_after != vitality_before:
		var vitality_event := CombatEventTypes.CARD_POINTS_CHANGED if target["kind"] == &"card" else CombatEventTypes.HEALTH_CHANGED
		writer.set_value(vitality_path, vitality_after, vitality_event, effect.source_entity_id, {
			"delta": vitality_after - vitality_before,
		})
	writer.emit_event(CombatEventTypes.DAMAGE_APPLIED, effect.source_entity_id, {
		"incoming": incoming,
		"absorbed": absorbed,
		"applied": applied,
		"shield_before": shield_before,
		"shield_after": shield_after,
		"vitality_before": vitality_before,
		"vitality_after": vitality_after,
	}, [entity_id])
	return CombatValidationResult.accepted()
