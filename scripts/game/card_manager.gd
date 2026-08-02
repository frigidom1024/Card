extends Node2D

## CardManager — 卡牌工厂
##
## 只负责两件事：
## 1. 从静态定义创建 CardInstance（数据层）
## 2. 创建 CardEntity（视觉节点）
## 不维护卡牌状态，不引用区域。

@export var card_scene: PackedScene
@export var card_lib: CardLibrary


# =========================
# 数据工厂：生成 CardInstance
# =========================

## 按预设的固定顺序创建本局起始卡牌。
## 该方法不会修改 StartingDeckData 或 CardData，且每次调用都会创建新的 CardInstance。
func create_starting_instances(starting_deck: StartingDeckData) -> Array[CardInstance]:
	if starting_deck == null or not starting_deck.validate().is_empty():
		push_error("CardManager: invalid StartingDeckData")
		return []

	var result: Array[CardInstance] = []
	for card_data in starting_deck.starter_cards:
		result.append(CardInstance.new(card_data))
	return result


# =========================
# 视觉工厂：创建 CardEntity 节点
# =========================

## 根据 CardInstance 实例化一张卡牌实体（未添加到场景树）
func create_card_entity(inst: CardInstance) -> CardEntity:
	if not card_scene:
		push_error("CardManager: card_scene 未设置")
		return null

	var card = card_scene.instantiate() as CardEntity
	card.bind_instance(inst)
	return card
