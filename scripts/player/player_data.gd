class_name PlayerData
extends Resource

signal gold_changed(current_gold: int)

const INITIAL_FAITH := 3

@export var player_name: String = "Player"
@export var base_stats: CombatStatsData
@export var gold: int = 30
# Run-scoped belief resource. GameManager resets it after duplicating this data for a new run.
@export var faith: int = INITIAL_FAITH


func set_gold(value: int) -> void:
	var normalized := maxi(value, 0)
	if normalized == gold:
		return
	gold = normalized
	gold_changed.emit(gold)


func add_gold(amount: int) -> int:
	if amount <= 0:
		return gold
	set_gold(gold + amount)
	return gold


func can_afford(amount: int) -> bool:
	return amount >= 0 and gold >= amount


func spend_gold(amount: int) -> bool:
	if not can_afford(amount):
		return false
	set_gold(gold - amount)
	return true
