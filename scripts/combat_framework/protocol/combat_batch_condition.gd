class_name CombatBatchCondition
extends RefCounted

## 具体条件通过继承此类，在批次真正出队执行时读取最新快照进行验证。
func validate(_snapshot: CombatStateSnapshot) -> CombatValidationResult:
	return CombatValidationResult.accepted()
