class_name EventTreasureContent
extends EventContent

const CardDataScript = preload("res://scripts/card/card_data.gd")

## 金币奖励范围（最小值 最大值）
@export var gold_range: Vector2i = Vector2i(3, 7)
## 卡牌奖励池（从这些卡中随机抽取）
@export var card_rewards: Array[CardDataScript] = []
## 遗留序列化字段；事件运行时始终从池中提供最多两张唯一普通卡。
@export var card_draw_count: int = 1
## 遗留序列化字段；EventRewardResolver 固定生成两张卡和一项金币。
@export var choices: int = 2


func unique_card_count() -> int:
	return _unique_cards().size()


func draw_unique_choices(count: int, rng: RandomNumberGenerator) -> Array[CardDataScript]:
	var pool := _unique_cards()
	for index in range(pool.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var swap_card := pool[index]
		pool[index] = pool[swap_index]
		pool[swap_index] = swap_card

	var result: Array[CardDataScript] = []
	for index in mini(count, pool.size()):
		result.append(pool[index])
	return result


func _unique_cards() -> Array[CardDataScript]:
	var unique_cards: Array[CardDataScript] = []
	for card in card_rewards:
		if card != null and not unique_cards.has(card):
			unique_cards.append(card)
	return unique_cards