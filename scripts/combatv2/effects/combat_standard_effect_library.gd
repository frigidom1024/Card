class_name CombatStandardEffectLibrary
extends RefCounted

const DamageEffectHandlerScript = preload("res://scripts/combatv2/effects/handlers/combat_damage_effect_handler.gd")
const ModifyShieldEffectHandlerScript = preload("res://scripts/combatv2/effects/handlers/combat_modify_shield_effect_handler.gd")
const ModifyCardPointsEffectHandlerScript = preload("res://scripts/combatv2/effects/handlers/combat_modify_card_points_effect_handler.gd")
const SpendGoldEffectHandlerScript = preload("res://scripts/combatv2/effects/handlers/combat_spend_gold_effect_handler.gd")
const GainGoldEffectHandlerScript = preload("res://scripts/combatv2/effects/handlers/combat_gain_gold_effect_handler.gd")
const SplitChainEffectHandlerScript = preload("res://scripts/combatv2/effects/handlers/combat_split_chain_effect_handler.gd")
const SetPhaseEffectHandlerScript = preload("res://scripts/combatv2/effects/handlers/combat_set_phase_effect_handler.gd")
const CardDeathStateRuleScript = preload("res://scripts/combatv2/effects/rules/combat_card_death_state_rule.gd")
const MonsterDeathStateRuleScript = preload("res://scripts/combatv2/effects/rules/combat_monster_death_state_rule.gd")


static func create_registry() -> CombatEffectHandlerRegistry:
	var registry := CombatEffectHandlerRegistry.new()
	registry.register(DamageEffectHandlerScript.new())
	registry.register(ModifyShieldEffectHandlerScript.new())
	registry.register(ModifyCardPointsEffectHandlerScript.new())
	registry.register(SpendGoldEffectHandlerScript.new())
	registry.register(GainGoldEffectHandlerScript.new())
	registry.register(SplitChainEffectHandlerScript.new())
	registry.register(SetPhaseEffectHandlerScript.new())
	return registry


static func create_processor(
	initial_data: Dictionary = {},
	initial_phase: StringName = &"idle"
) -> CombatEffectBatchProcessor:
	var state := CombatRuntimeState.new()
	state.initialize(initial_data, initial_phase)
	var processor := CombatEffectBatchProcessor.new(state, create_registry())
	processor.add_state_rule(CardDeathStateRuleScript.new())
	processor.add_state_rule(MonsterDeathStateRuleScript.new())
	return processor
