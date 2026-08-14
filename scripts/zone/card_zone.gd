## 卡牌区域基础组件
##
## 负责定义所有卡牌区域共享的空间查询与拖拽协议。
## 包括：
## - 区域范围命中判断
## - 卡牌成员所有权查询
## - 卡牌接收、移除与拖拽生命周期接口
##
## 不负责：
## - 具体区域的卡牌布局与业务规则
## - 卡牌实例状态的统一存储
## - 跨区域拖拽流程的来源解析与提交顺序
##
## 使用方式：
## 由具体区域继承并实现 owns_card()、add_card() 以及需要的拖拽协议方法，
## 再由 DraggerLayer 注册和协调这些区域。
##
## 依赖：
## Card：作为区域拖拽协议和成员所有权判断的卡牌视图。

class_name CardZone
extends Control


func contains_global_point(global_point: Vector2) -> bool:
	return get_global_rect().has_point(global_point)


func in_zone(global_point: Vector2) -> bool:
	return contains_global_point(global_point)


func add_card(card: Card, keep_global_position: bool = true) -> bool:
	return false


func remove_card(card: Card) -> bool:
	return false


func get_cards() -> Array[Card]:
	return []


func owns_card(_card: Card) -> bool:
	return false


## Notification to the source zone that a card has started dragging.
func start_drag(card: Card) -> void:
	pass


## Updates this zone's temporary preview while a card is dragged over it.
func update_drag(card: Card) -> void:
	pass


## Whether this zone accepts the dragged card as a target.
func can_trans_to_target(card: Card) -> bool:
	return false


## Whether this zone allows the dragged card to leave as a source.
func can_trans_from_source(card: Card) -> bool:
	return false


## Called on the source zone when the drag ends.
func drag_end_source(card: Card, ok: bool) -> bool:
	return true


## Called on the target zone when the drag ends.
## Returns whether the target accepted and committed the card.
func drag_end_target(card: Card, ok: bool) -> bool:
	return false


func name()->String:
	return ""
