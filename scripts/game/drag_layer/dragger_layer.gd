## 卡牌拖拽协调组件
##
## 负责协调当前页面中 Card 与已注册 CardZone 之间的拖拽流程。
## 包括：
## - 注册和注销可交互区域
## - 根据卡牌变换后的中心点解析目标区域
## - 在拖拽开始时解析并缓存唯一来源区域
## - 按来源先提交、目标后提交的顺序结束拖拽
##
## 不负责：
## - 卡牌节点的位置运动与视觉反馈
## - 各区域内部的布局、规则判断与业务结算
## - 卡牌实例状态的直接写入
##
## 使用方式：
## 页面创建唯一 DraggerLayer 后注册 HandZone、BoardZone、ShopZone 和 ReclaimZone；
## Card 通过 bind_drag_layer() 接入，并由本组件接收 start_drag/update_drag/end_drag 通知。
##
## 依赖：
## Card：提供拖拽卡牌视图与变换后的中心点。
## CardZone：提供区域命中、所有权和拖拽事务协议。

class_name DraggerLayer
extends Node

var _registered_zones: Array[CardZone] = []
var _interaction_locked := false
var dragging_card: Card
var _drag_source: CardZone
var _preview_target: CardZone


func set_interaction_locked(locked: bool) -> void:
	_interaction_locked = locked


func is_interaction_locked() -> bool:
	return _interaction_locked


func register_zone(zone: CardZone) -> void:
	if zone != null and zone not in _registered_zones:
		_registered_zones.append(zone)


func unregister_zone(zone: CardZone) -> void:
	_registered_zones.erase(zone)
	if _preview_target == zone:
		_preview_target = null


func get_zone_at(global_point: Vector2) -> CardZone:
	for zone in _registered_zones:
		if is_instance_valid(zone) and zone.contains_global_point(global_point):
			return zone
	return null


func get_registered_zones() -> Array[CardZone]:
	var valid_zones: Array[CardZone] = []
	for zone in _registered_zones:
		if is_instance_valid(zone):
			valid_zones.append(zone)
	_registered_zones = valid_zones
	return valid_zones


func start_drag(card: Card) -> bool:
	if _interaction_locked or card == null or dragging_card != null:
		return false

	var owners := _find_card_owners(card)
	if owners.size() > 1:
		push_warning("DraggerLayer found multiple owners for Card: %s" % card)
		return false

	dragging_card = card
	_drag_source = owners[0] if owners.size() == 1 else null
	_preview_target = null

	if _drag_source != null:
		if not _drag_source.can_trans_from_source(card):
			dragging_card = null
			_drag_source = null
			return false
		_drag_source.start_drag(card)
	return true


func update_drag(card: Card) -> void:
	if card == null or card != dragging_card:
		return

	var target := get_zone_at(_get_card_center(card))
	if target != null and not target.can_trans_to_target(card):
		target = null

	if _preview_target != null and _preview_target != target:
		_preview_target.drag_end_target(card, false)
		_preview_target = null

	if target != null:
		target.update_drag(card)
		_preview_target = target


func end_drag(card: Card) -> bool:
	if card == null or card != dragging_card:
		return false

	update_drag(card)
	var target := _preview_target
	var target_valid := target != null and target.can_trans_to_target(card)

	if _drag_source!=null and !_drag_source.can_trans_from_source(card):
		target_valid=false
	if _drag_source:
		_drag_source.drag_end_source(card,target_valid)
	if target:
		target.drag_end_target(card,target_valid)

	dragging_card = null
	_drag_source = null
	_preview_target = null
	return true


func _find_card_owners(card: Card) -> Array[CardZone]:
	var owners: Array[CardZone] = []
	for zone in get_registered_zones():
		if zone.owns_card(card):
			owners.append(zone)
	return owners


func _get_card_center(card: Card) -> Vector2:
	return card.get_global_transform_with_canvas() * (card.size * 0.5)
