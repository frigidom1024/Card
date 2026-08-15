class_name CombatEffectBatchResult
extends RefCounted

enum Status { COMMITTED, CANCELED, FAILED }

var status: Status = Status.FAILED
var batch_id: String = ""
var batch_type: CombatEffectBatch.Type = CombatEffectBatch.Type.FLOW_TRANSITION
var source_type: CombatEffectBatch.SourceType = CombatEffectBatch.SourceType.BATTLE_DRIVER
var state_revision: int = -1
var chain_revision: int = -1
var reason_code: StringName = &""
var message: String = ""
var events: Array[CombatStateEvent] = []


func is_committed() -> bool:
	return status == Status.COMMITTED
