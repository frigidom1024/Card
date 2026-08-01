class_name CombatContext
extends RefCounted

var player_stats: CombatStats
var monster: MobInstance
var cards: Array[CardInstance]
var resolved_cards: Array[CardInstance] = []
var remaining_cards: Array[CardInstance]
var steps: Array[CombatStep] = []
var current_batch_id := 0
var current_batch_card_count := 0


func _init(
	player_stats_copy: CombatStats, monster_copy: MobInstance, cards: Array[CardInstance]
) -> void:
	player_stats = player_stats_copy
	monster = _duplicate_monster(monster_copy)
	self.cards = cards.duplicate()
	remaining_cards = cards.duplicate()


static func _duplicate_monster(source: MobInstance) -> MobInstance:
	if source == null:
		return null
	var copy := MobInstance.new(source.data)
	copy.stats = source.stats.duplicate_runtime() if source.stats else null
	copy.action_index = source.action_index
	return copy
