class_name CombatStateDraft
extends RefCounted

var base_state_revision: int = 0
var state_revision: int = 0
var chain_revision: int = 0
var phase: StringName = &"idle"
var data: Dictionary = {}
var changed: bool = false
var chain_changed: bool = false
var events: Array[CombatStateEvent] = []


func create_snapshot() -> CombatStateSnapshot:
	var snapshot := CombatStateSnapshot.new()
	snapshot.state_revision = state_revision
	snapshot.chain_revision = chain_revision
	snapshot.phase = phase
	snapshot.data = data.duplicate(true)
	return snapshot
