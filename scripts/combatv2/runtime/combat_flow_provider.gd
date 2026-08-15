class_name CombatFlowProvider
extends RefCounted

## 战斗驱动通过本端口获取下一批自动战斗效果。
## 实际战斗流程可以在后续实现中管理牌链游标、玩家攻击和怪物攻击阶段。
func start(_snapshot: CombatStateSnapshot) -> void:
	pass


func build_next_batch(
	_snapshot: CombatStateSnapshot,
	_last_result: CombatEffectBatchResult
) -> CombatEffectBatch:
	return null


func on_batch_finished(
	_result: CombatEffectBatchResult,
	_snapshot: CombatStateSnapshot
) -> void:
	pass


func is_finished(_snapshot: CombatStateSnapshot) -> bool:
	return false
