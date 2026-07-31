class_name CombatStep
extends RefCounted

enum Kind { ROOT_CARD, PLAYER_CARD, MONSTER_ACTION }

var kind: Kind
var source_name: String
var effects: Array[CombatEffect]
var player_before: CombatStats
var player_after: CombatStats
var monster_before: CombatStats
var monster_after: CombatStats


func _init(
	kind: Kind,
	source_name: String,
	effects: Array[CombatEffect],
	player_before: CombatStats,
	player_after: CombatStats,
	monster_before: CombatStats,
	monster_after: CombatStats
) -> void:
	self.kind = kind
	self.source_name = source_name
	self.effects = []
	for effect in effects:
		self.effects.append(effect.duplicate_runtime() if effect else null)
	self.player_before = player_before.duplicate_runtime() if player_before else null
	self.player_after = player_after.duplicate_runtime() if player_after else null
	self.monster_before = monster_before.duplicate_runtime() if monster_before else null
	self.monster_after = monster_after.duplicate_runtime() if monster_after else null


func duplicate_runtime() -> CombatStep:
	return CombatStep.new(
		kind, source_name, effects, player_before, player_after, monster_before, monster_after
	)
