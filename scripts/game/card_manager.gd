extends Node2D

## CardManager — 卡牌工厂
##
## 只负责两件事：
## 1. 创建 CardInstance（数据层）
## 2. 创建 CardEntity（视觉节点）
## 不维护卡牌状态，不引用区域。

@export var card_scene: PackedScene
@export var card_lib: CardLibrary



# =========================
# 数据工厂：生成 CardInstance
# =========================

# 玩家初始卡牌（1 张牌根 + 其余随机 80% Common / 20% Rare，可重复）
func get_init_cards(total: int = 5) -> Array[CardInstance]:
	if not card_lib or card_lib.cards.is_empty():
		push_error("CardManager: card_lib 为空，无法生成初始卡牌")
		return []

	# 1. 找牌根（ROOT 类型）
	var root_data: CardData = null
	for card_data in card_lib.cards:
		if card_data.card_type == CardData.CardType.ROOT:
			root_data = card_data
			break
	if not root_data:
		push_error("CardManager: 找不到 ROOT 类型的牌根卡")
		return []

	# 2. 其余卡牌按稀有度拆池（排除 ROOT 卡）
	var common_pool: Array[CardData] = []
	var rare_pool: Array[CardData] = []
	for card_data in card_lib.cards:
		if card_data.card_type == CardData.CardType.ROOT:
			continue
		match card_data.rarity:
			CardData.Rarity.COMMON:
				common_pool.append(card_data)
			CardData.Rarity.RARE:
				rare_pool.append(card_data)

	# 3. 构造结果：牌根 + 随机卡
	var result: Array[CardInstance] = [CardInstance.new(root_data)]
	var remain = total - 1
	for i in range(remain):
		var pool: Array[CardData]
		if randf() < 0.8:
			pool = common_pool
		else:
			pool = rare_pool

		if pool.is_empty():
			pool = rare_pool if pool == common_pool else common_pool
		if pool.is_empty():
			push_error("CardManager: 没有可用的卡牌数据")
			break

		var picked = pool[randi() % pool.size()]
		result.append(CardInstance.new(picked))

	return result


# =========================
# 视觉工厂：创建 CardEntity 节点
# =========================

# 根据 CardInstance 实例化一张卡牌实体（未添加到场景树）
func create_card_entity(inst: CardInstance) -> CardEntity:
	if not card_scene:
		push_error("CardManager: card_scene 未设置")
		return null

	var card = card_scene.instantiate() as CardEntity
	card.bind_instance(inst)
	return card
