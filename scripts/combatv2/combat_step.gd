class_name CombatStep
extends RefCounted

enum Kind { ROOT_CARD, PLAYER_CARD, MONSTER_ACTION, COMBAT_START, COMBAT_END, PRE_COMBAT_CARD }

var kind: Kind
var source_name: String
var effects: Array[CombatEffect]
var player_before: CombatStats
var player_after: CombatStats
var monster_before: CombatStats
var monster_after: CombatStats
## Point and armor snapshots make a point clash readable without coupling UI to
## the mutable CardInstance that lives on the board.
var card_points_before: int
var card_points_after: int
var card_armor_before: int
var card_armor_after: int


func _init(
	kind: Kind,
	source_name: String,
	effects: Array[CombatEffect],
	player_before: CombatStats,
	player_after: CombatStats,
	monster_before: CombatStats,
	monster_after: CombatStats,
	card_points_before: int = 0,
	card_points_after: int = 0,
	card_armor_before: int = 0,
	card_armor_after: int = 0
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
	self.card_points_before = maxi(card_points_before, 0)
	self.card_points_after = maxi(card_points_after, 0)
	self.card_armor_before = maxi(card_armor_before, 0)
	self.card_armor_after = maxi(card_armor_after, 0)


func duplicate_runtime() -> CombatStep:
	return CombatStep.new(
		kind,
		source_name,
		effects,
		player_before,
		player_after,
		monster_before,
		monster_after,
		card_points_before,
		card_points_after,
		card_armor_before,
		card_armor_after
	)
