class_name EventTreasureContent
extends Resource

## 金币奖励范围（最小值 最大值）
@export var gold_range: Vector2i = Vector2i(3, 7)
## 卡牌奖励池（从这些卡中随机抽取）
@export var card_rewards: Array[CardData] = []
## 抽取卡牌数量（0=不抽卡）
@export var card_draw_count: int = 1
## 选项数（0=直接获得，3=三选一）
@export var choices: int = 0


## 生成金币数量
func get_gold() -> int:
	return randi_range(gold_range.x, gold_range.y)


## 抽取卡牌奖励
func draw_cards() -> Array[CardData]:
	if card_rewards.is_empty() or card_draw_count == 0:
		return []

	var pool = card_rewards.duplicate()
	pool.shuffle()

	# 不重复抽取
	var result: Array[CardData] = []
	var count = mini(card_draw_count, pool.size())
	for i in count:
		result.append(pool[i])
	return result


## 获取选项卡牌（choices > 0 时使用）
func get_choices() -> Array[CardData]:
	var pool = card_rewards.duplicate()
	pool.shuffle()
	var count = mini(choices, pool.size())
	var result: Array[CardData] = []
	for i in count:
		result.append(pool[i])
	return result
