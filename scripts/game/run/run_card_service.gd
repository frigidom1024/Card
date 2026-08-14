## 运行卡牌服务组件
##
## 负责管理当前游戏流程拥有的 CardInstance 与可见 Card 的精确一一对应关系。
## 包括：
## - 从初始牌组或奖励数据创建运行期 CardInstance
## - 创建、绑定并跟踪对应的 Card 视图
## - 将新卡或已有卡放入 HandZone
## - 注销、销毁和清理当前流程拥有的卡牌
## - 在精确运行卡集合变化后发出同步通知
##
## 不负责：
## - 手牌容量、布局或拖拽合法性规则
## - 商店定价、金币结算或牌桌业务判断
## - CardInstance 的跨局持久化
##
## 使用方式：
## 先通过 configure() 注入 Card 场景、HandZone 和唯一 DraggerLayer，
## 再调用 initialize_starting_deck()、grant_to_hand() 或精确实例登记接口。
##
## 依赖：
## Card：提供运行期卡牌视图与显示刷新。
## CardInstance：保存卡牌唯一业务状态。
## HandZone：接收和管理手牌成员。
## DraggerLayer：协调页面内所有卡牌区域的同步拖拽。

class_name RunCardService
extends RefCounted

signal cards_changed

var card_scene: PackedScene
var hand_zone: HandZone
var drag_layer: DraggerLayer

var _instances: Array[CardInstance] = []
var _card_views: Array[Card] = []


func configure(
	next_card_scene: PackedScene,
	next_hand_zone: HandZone,
	next_drag_layer: DraggerLayer
) -> bool:
	if next_card_scene == null or next_hand_zone == null or next_drag_layer == null:
		return false
	card_scene = next_card_scene
	hand_zone = next_hand_zone
	drag_layer = next_drag_layer
	return true


func initialize_starting_deck(starting_deck: StartingDeckData) -> bool:
	if not _is_configured() or starting_deck == null or not starting_deck.validate().is_empty():
		return false
	clear()

	for card_data in starting_deck.starter_cards:
		if card_data == null or not _add_new_instance_to_hand(CardInstance.new(card_data)):
			clear()
			return false
	return true


func grant_to_hand(card_data: CardData) -> bool:
	if not _is_configured() or card_data == null:
		return false
	return _add_new_instance_to_hand(CardInstance.new(card_data))


## 兼容遭遇奖励流程；HandZone 本身不实现容量限制，因此无需临时扩容。
func grant_to_hand_temporarily(card_data: CardData) -> bool:
	return grant_to_hand(card_data)


## 将服务已跟踪的 Card 精确实例重新交给 HandZone。
## allow_overflow 仅保留旧业务接口兼容性，HandZone 当前没有容量规则。
func return_existing_to_hand(card: Card, _allow_overflow := false) -> bool:
	if (
		not _is_configured()
		or card == null
		or not is_instance_valid(card)
		or hand_zone.owns_card(card)
		or card not in _card_views
	):
		return false
	return hand_zone.add_card(card)


## 兼容战斗撤退流程；当前语义与普通回手一致。
func return_existing_to_hand_temporarily(card: Card) -> bool:
	return return_existing_to_hand(card, true)


## 仅解除运行服务的精确实例跟踪，不删除 Card，也不修改区域成员关系。
func forget_card(card: Card) -> bool:
	var index := _card_views.find(card)
	if index == -1:
		return false
	_card_views.remove_at(index)
	_instances.remove_at(index)
	_notify_cards_changed()
	return true


## 兼容旧调用名称，销毁 Card 当前绑定且由本服务跟踪的精确实例。
func destroy_existing_card(card: Card) -> bool:
	if card == null:
		return false
	return destroy_existing_instance(card.get_card_inst(), card)


func clear() -> void:
	for card in _card_views.duplicate():
		if card == null or not is_instance_valid(card):
			continue
		if hand_zone != null and is_instance_valid(hand_zone) and hand_zone.owns_card(card):
			hand_zone.remove_card(card)
		card.bind_drag_layer(null)
		card.queue_free()
	_card_views.clear()
	_instances.clear()
	_notify_cards_changed()


func get_instances() -> Array[CardInstance]:
	return _instances.duplicate()


## 兼容旧业务接口；新流程返回 Card，而不是 CardEntity。
func get_entities() -> Array[Card]:
	return get_card_views()


func get_card_views() -> Array[Card]:
	return _card_views.duplicate()


func can_register_existing_instance(card_inst: CardInstance, card: Card) -> bool:
	if (
		card_inst == null
		or card_inst.card_data == null
		or card == null
		or not is_instance_valid(card)
		or card.get_card_inst() != card_inst
	):
		return false

	var instance_index := _instances.find(card_inst)
	var card_index := _card_views.find(card)
	if instance_index != -1 or card_index != -1:
		return (
			instance_index != -1
			and card_index != -1
			and instance_index == card_index
		)
	return true


func register_existing_instance(card_inst: CardInstance, card: Card) -> bool:
	if not can_register_existing_instance(card_inst, card):
		return false
	if card_inst in _instances:
		return true
	_instances.append(card_inst)
	_card_views.append(card)
	card_inst.cur_zone = CardInstance.ZONE.HAND
	card.refresh_display()
	_notify_cards_changed()
	return true


func can_destroy_existing_instance(card_inst: CardInstance, card: Card) -> bool:
	if (
		card_inst == null
		or card == null
		or not is_instance_valid(card)
		or card.get_card_inst() != card_inst
	):
		return false
	var instance_index := _instances.find(card_inst)
	var card_index := _card_views.find(card)
	return instance_index != -1 and instance_index == card_index


func destroy_existing_instance(card_inst: CardInstance, card: Card) -> bool:
	if not can_destroy_existing_instance(card_inst, card):
		return false

	if hand_zone != null and is_instance_valid(hand_zone) and hand_zone.owns_card(card):
		hand_zone.remove_card(card)
	var index := _instances.find(card_inst)
	_instances.remove_at(index)
	_card_views.remove_at(index)
	card_inst.cur_zone = CardInstance.ZONE.DISCARD
	card_inst.battlefield_pos = Vector2i(-1, -1)
	card_inst.direction = 0
	card.refresh_display()
	card.bind_drag_layer(null)
	card.queue_free()
	_notify_cards_changed()
	return true


func _add_new_instance_to_hand(instance: CardInstance) -> bool:
	if instance == null:
		return false
	var card := _create_view(instance)
	if card == null:
		return false
	if not hand_zone.add_card(card):
		card.queue_free()
		return false
	_instances.append(instance)
	_card_views.append(card)
	_notify_cards_changed()
	return true


func _notify_cards_changed() -> void:
	cards_changed.emit()


func _create_view(instance: CardInstance) -> Card:
	if card_scene == null or instance == null:
		return null
	var created_node := card_scene.instantiate()
	var card := created_node as Card
	if card == null:
		created_node.free()
		return null
	card.bind_card_inst(instance)
	card.bind_drag_layer(drag_layer)
	return card


func _is_configured() -> bool:
	return card_scene != null and hand_zone != null and drag_layer != null
