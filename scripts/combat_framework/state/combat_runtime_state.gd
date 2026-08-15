class_name CombatRuntimeState
extends RefCounted

## 正式战斗状态。运行期只有 EffectBatchProcessor 持有写入能力。
var _state_revision: int = 0
var _chain_revision: int = 0
var _phase: StringName = &"idle"
var _data: Dictionary = {}


func initialize(initial_data: Dictionary = {}, initial_phase: StringName = &"idle") -> void:
	_state_revision = 0
	_chain_revision = 0
	_phase = initial_phase
	_data = initial_data.duplicate(true)


func create_snapshot() -> CombatStateSnapshot:
	var snapshot := CombatStateSnapshot.new()
	snapshot.state_revision = _state_revision
	snapshot.chain_revision = _chain_revision
	snapshot.phase = _phase
	snapshot.data = _data.duplicate(true)
	return snapshot


func _begin_draft() -> CombatStateDraft:
	var draft := CombatStateDraft.new()
	draft.base_state_revision = _state_revision
	draft.state_revision = _state_revision
	draft.chain_revision = _chain_revision
	draft.phase = _phase
	draft.data = _data.duplicate(true)
	return draft


func _commit_draft(draft: CombatStateDraft) -> CombatStateSnapshot:
	if draft == null:
		return create_snapshot()
	_state_revision += 1
	_state_revision = maxi(_state_revision, draft.base_state_revision + 1)
	_chain_revision = draft.chain_revision
	_phase = draft.phase
	_data = draft.data.duplicate(true)
	return create_snapshot()
