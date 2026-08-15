class_name CombatStateRule
extends RefCounted

## 每个效果应用后执行，例如死亡检查、牌链完整性检查。
func evaluate(
	_effect: CombatBatchEffect,
	_writer: CombatStateWriter
) -> CombatValidationResult:
	return CombatValidationResult.accepted()
