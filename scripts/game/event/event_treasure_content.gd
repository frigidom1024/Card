class_name EventTreasureContent
extends Resource

## 金币奖励范围（最小值 最大值）
@export var gold_range: Vector2i = Vector2i(3, 7)
## 卡牌奖励池（从这些卡中随机抽取）
@export var card_rewards: Array[CardData] = []
## 抽取卡牌数量（0=不抽卡）
@export var card_draw_count: int = 1
## 选项数（默认两张卡牌加一个金币选项）
@export var choices: int = 2


func draw_unique_choices(count: int, rng: RandomNumberGenerator) -> Array[CardData]:
	var pool: Array[CardData] = []
	for card in card_rewards:
		if card != null and not pool.has(card):
			pool.append(card)

	for index in range(pool.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var swap_card := pool[index]
		pool[index] = pool[swap_index]
		pool[swap_index] = swap_card

	var result: Array[CardData] = []
	for index in mini(count, pool.size()):
		result.append(pool[index])
	return result
