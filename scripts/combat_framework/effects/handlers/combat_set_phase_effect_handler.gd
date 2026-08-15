class_name CombatSetPhaseEffectHandler
extends CombatEffectHandler


func _init() -> void:
	super(&"set_phase")


func validate(effect: CombatBatchEffect, _snapshot: CombatStateSnapshot) -> CombatValidationResult:
	if not effect.parameters.has("phase") or StringName(effect.get_parameter("phase", &"")) == &"":
		return CombatValidationResult.rejected(&"missing_phase", "阶段效果缺少 phase")
	return CombatValidationResult.accepted()


func apply(effect: CombatBatchEffect, writer: CombatStateWriter) -> CombatValidationResult:
	writer.set_phase(StringName(effect.get_parameter("phase", &"")))
	return CombatValidationResult.accepted()
