class_name CombatContext
extends RefCounted

var player_stats: CombatStats
var monster: MobInstance
var cards: Array[CardInstance]
var resolved_cards: Array[CardInstance] = []
var remaining_cards: Array[CardInstance]
var depleted_cards: Array[CardInstance] = []
## Cards that have already used a one-time positional combat trigger.
var pre_resolved_cards: Array[CardInstance] = []
var steps: Array[CombatStep] = []
var current_batch_id := 0
var current_batch_card_count := 0
## Combat-only point grants are tracked separately from persistent card points
## so encounter cleanup cannot leave temporary bonuses on the board.
var temporary_card_points: Dictionary = {}


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
	return source.duplicate_for_encounter()


func register_temporary_card_points(card: CardInstance, amount: int) -> void:
	if card == null or amount <= 0:
		return
	temporary_card_points[card] = get_temporary_card_points(card) + amount


func get_temporary_card_points(card: CardInstance) -> int:
	return int(temporary_card_points.get(card, 0)) if card != null else 0


func clear_temporary_card_points(card: CardInstance) -> void:
	if card != null:
		temporary_card_points.erase(card)
