extends RefCounted
class_name CardInstance

@export var card_data: CardData = null

enum ZONE {
	DRAW,
	HAND,
	BOARD,
	DISCARD,
	DRAGLAYER
}

var cur_zone: ZONE

var battlefield_pos := Vector2i(-1, -1)
var direction: int = 0

## Persistent runtime combat state. Points and armor survive until a combat or
## rule effect changes them; CardData only supplies their starting values.
var current_points: int = 0
var current_armor: int = 0

## Keyed by the owning card data's rule index. Keeping this state on the card
## instance prevents one card copy from consuming another copy's rule uses.
var _rule_trigger_counts: Dictionary = {}


func _init(data: CardData):
	card_data = data
	reset_points()
	reset_armor()


func reset_points() -> void:
	current_points = maxi(card_data.max_points, 0) if card_data != null else 0


func add_points(amount: int) -> int:
	var granted := maxi(amount, 0)
	current_points += granted
	return granted


func consume_points(amount: int) -> int:
	var consumed := mini(maxi(amount, 0), current_points)
	current_points -= consumed
	return consumed


func is_depleted() -> bool:
	return current_points <= 0


func reset_armor() -> void:
	current_armor = maxi(card_data.armor, 0) if card_data != null else 0


func add_armor(amount: int) -> int:
	var granted := maxi(amount, 0)
	current_armor += granted
	return granted


func consume_armor(amount: int) -> int:
	var consumed := mini(maxi(amount, 0), current_armor)
	current_armor -= consumed
	return consumed


func get_rule_trigger_count(rule_index: int) -> int:
	return int(_rule_trigger_counts.get(rule_index, 0))


func can_trigger_rule(rule_index: int, effective_count: int) -> bool:
	if effective_count < 0:
		return true
	return get_rule_trigger_count(rule_index) < effective_count


func record_rule_trigger(rule_index: int) -> void:
	_rule_trigger_counts[rule_index] = get_rule_trigger_count(rule_index) + 1


# ========== 调试专用：生成默认测试卡牌 ==========
static func create_debug_card() -> CardInstance:
	var data = load("res://data/cards/AllThingsRevival.tres") as CardData
	return CardInstance.new(data)
