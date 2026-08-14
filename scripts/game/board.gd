## 牌桌业务协调组件
##
## 负责连接卡牌牌桌区域与事件牌桌区域，并把已提交的空间事实转换为业务信号。
## 包括：
## - 接收 BoardZone 的直接放置与拆链事实
## - 组织 GUIDE 返回手牌和牌链后继卡牌回收
## - 管理事件挂载、移动、删除等业务入口
## - 发布放置、回手、拆链确认和事件生命周期信号
##
## 不负责：
## - 卡牌格子索引、占用判断或拖拽来源解析
## - 保存或恢复卡牌视觉快照
## - 事件格子索引、缓冲区判断或事件生成
## - 手牌、商店、回收区的成员管理
## - DraggerLayer 注册和页面级回手处理
##
## 使用方式：
## 在场景中注入 BoardZone 与 BoardEventZone；页面连接业务信号，
## 并通过 attach_event()、move_event()、remove_event() 管理事件节点。
##
## 依赖：
## BoardZone：执行卡牌空间事务并发布直接事实参数。
## BoardEventZone：执行事件空间事务并提供重叠查询。
## BoardPlacementResult / ChainRetractionTransaction：对外业务结果。
## Card / BoardEvent / EventInstance：业务对象类型。

class_name Board
extends Node2D

@export var board_zone: BoardZone
@export var event_zone: BoardEventZone

signal placement_committed(result: BoardPlacementResult)
signal card_return_requested(card: Card)
signal chain_retraction_confirmed(transaction: ChainRetractionTransaction)
signal event_triggered(instance: EventInstance)
signal event_attached(event_node: BoardEvent)
signal event_removed(event_node: BoardEvent)


func _ready() -> void:
	_resolve_child_dependencies()
	if board_zone == null or not is_instance_valid(board_zone):
		push_error("Board requires a BoardZone child")
		return
	if event_zone == null or not is_instance_valid(event_zone):
		push_error("Board requires a BoardEventZone child")
		return
	if not board_zone.card_placed.is_connected(_on_card_placed):
		board_zone.card_placed.connect(_on_card_placed)
	if not board_zone.chain_detached.is_connected(_on_chain_detached):
		board_zone.chain_detached.connect(_on_chain_detached)


func attach_event(event_node: BoardEvent) -> bool:
	if event_zone == null or not is_instance_valid(event_zone):
		return false
	if not event_zone.attach_event(event_node):
		return false
	event_attached.emit(event_node)
	return true


func move_event(event_node: BoardEvent, target_origin: Vector2i) -> bool:
	if event_zone == null or not is_instance_valid(event_zone):
		return false
	return event_zone.move_event(event_node, target_origin)


func remove_event(event_node: BoardEvent) -> bool:
	if event_zone == null or not is_instance_valid(event_zone):
		return false
	if not event_zone.remove_event(event_node):
		return false
	event_removed.emit(event_node)
	return true


func _resolve_child_dependencies() -> void:
	if board_zone == null:
		board_zone = get_node_or_null("BoardZone") as BoardZone
	if event_zone == null:
		event_zone = get_node_or_null("BoardEventZone") as BoardEventZone
	if event_zone == null or board_zone == null:
		return
	if event_zone.grid_source == null or not is_instance_valid(event_zone.grid_source):
		event_zone.grid_source = board_zone.back_ground
	if event_zone.card_zone == null or not is_instance_valid(event_zone.card_zone):
		event_zone.card_zone = board_zone


func _on_card_placed(
	card: Card,
	occupied_cells: Array[Vector2i],
	affected_cards: Array[Card],
	guide_resolved: bool
) -> void:
	if card == null or not is_instance_valid(card):
		return
	var result_kind := (
		BoardPlacementResult.Kind.GUIDE_RESOLVED
		if guide_resolved
		else BoardPlacementResult.Kind.CHAIN_EXTENDED
	)
	var overlapped_event: EventInstance = null
	if event_zone != null and is_instance_valid(event_zone):
		overlapped_event = event_zone.get_overlapping_unresolved_event(occupied_cells)
	var chain_tail := affected_cards.back() if not affected_cards.is_empty() else card
	var result := BoardPlacementResult.new(
		result_kind,
		card,
		chain_tail,
		affected_cards,
		occupied_cells,
		overlapped_event
	)
	placement_committed.emit(result)
	if guide_resolved:
		card_return_requested.emit(card)
	if overlapped_event != null:
		event_triggered.emit(overlapped_event)


func _on_chain_detached(
	removed_card: Card,
	followers_to_return: Array[Card],
	original_chain_size: int
) -> void:
	var transaction := ChainRetractionTransaction.new(
		removed_card,
		followers_to_return,
		original_chain_size
	)
	for follower: Card in transaction.returned_followers:
		if follower == null or not is_instance_valid(follower):
			return
		card_return_requested.emit(follower)
	for follower: Card in transaction.returned_followers:
		var card_inst := follower.get_card_inst() if follower != null and is_instance_valid(follower) else null
		if card_inst == null or card_inst.cur_zone != CardInstance.ZONE.HAND:
			push_error("Board chain retraction did not return every follower to Hand")
			return
	chain_retraction_confirmed.emit(transaction)
