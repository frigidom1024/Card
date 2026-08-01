class_name CombatResult
extends RefCounted

enum Outcome { VICTORY, RETREAT, DEFEAT }

var outcome: Outcome
var player_stats_after: CombatStats
var monster_stats_after: CombatStats
var steps: Array[CombatStep]
var processed_card_count: int
var penalties: Array[CombatPenalty]


func _init(
	outcome: Outcome,
	player_stats_after: CombatStats,
	monster_stats_after: CombatStats,
	steps: Array[CombatStep],
	processed_card_count: int,
	penalties: Array[CombatPenalty]
) -> void:
	self.outcome = outcome
	self.player_stats_after = player_stats_after.duplicate_runtime() if player_stats_after else null
	self.monster_stats_after = (
		monster_stats_after.duplicate_runtime() if monster_stats_after else null
	)
	self.steps = []
	for step in steps:
		self.steps.append(step.duplicate_runtime() if step else null)
	self.processed_card_count = processed_card_count
	self.penalties = []
	for penalty in penalties:
		self.penalties.append(penalty)
