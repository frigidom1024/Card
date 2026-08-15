class_name CombatEffectHandler
extends RefCounted

var effect_type: StringName = &""


func _init(p_effect_type: StringName = &"") -> void:
	effect_type = p_effect_type


func validate(
	_effect: CombatBatchEffect,
	_snapshot: CombatStateSnapshot
) -> CombatValidationResult:
	return CombatValidationResult.accepted()


func apply(
	_effect: CombatBatchEffect,
	_writer: CombatStateWriter
) -> CombatValidationResult:
	return CombatValidationResult.accepted()
