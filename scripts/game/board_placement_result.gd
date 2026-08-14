## 牌桌业务放置结果
##
## 负责向牌桌业务消费者提供一次成功放置的不可变摘要。
## 包括：
## - 放置业务类型
## - 来源卡牌、牌链尾部与受影响卡牌
## - 新占用格子与重叠事件
##
## 不负责：
## - 修改牌桌空间状态
## - 解析或结算事件
## - 管理卡牌拖拽
##
## 使用方式：
## Board 将 BoardZone 的空间操作转换为本结果并通过 placement_committed 发布。
##
## 依赖：
## Card：公开卡牌视图；EventInstance：可能重叠的事件实例。
class_name BoardPlacementResult
extends RefCounted


enum Kind {
	CHAIN_EXTENDED,
	GUIDE_RESOLVED,
}

var kind: Kind
var source_card: Card
var chain_tail: Card
var affected_cards: Array[Card]
var newly_occupied_cells: Array[Vector2i]
var overlapped_event: EventInstance


func _init(
	initial_kind: Kind,
	initial_source_card,
	initial_chain_tail,
	initial_affected_cards: Array,
	initial_newly_occupied_cells: Array[Vector2i],
	initial_overlapped_event: EventInstance = null
) -> void:
	kind = initial_kind
	source_card = initial_source_card as Card
	chain_tail = initial_chain_tail as Card
	affected_cards.clear()
	for affected_card in initial_affected_cards:
		if affected_card is Card:
			affected_cards.append(affected_card)
	newly_occupied_cells = initial_newly_occupied_cells.duplicate()
	overlapped_event = initial_overlapped_event
