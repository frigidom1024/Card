class_name CombatBattleOutcome
extends RefCounted

const RUNNING: StringName = &"running"
const VICTORY: StringName = &"victory"
const RETREAT: StringName = &"retreat"
const DEFEAT: StringName = &"defeat"


static func is_terminal(outcome: StringName) -> bool:
	return outcome != RUNNING
