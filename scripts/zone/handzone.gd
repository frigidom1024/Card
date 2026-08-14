## 手牌区域组件
##
## 负责管理手牌成员、横向布局与手牌拖拽事务。
## 包括：
## - Card 的稳定成员集合与插入顺序
## - 手牌卡牌的重叠、旋转和浮动布局
## - 拖拽期间的临时布局预览与提交
## - 将接收的 CardInstance 规范化为 HAND 状态
##
## 不负责：
## - 卡牌数据的创建、持久化或购买规则
## - 其它区域的空间判断与拖拽来源解析
## - Board 牌链、商店补货或回收收益
##
## 使用方式：
## 先将 HandZone 注册到当前页面的 DraggerLayer，再通过 add_card() 接收卡牌；
## 跨区域拖拽由 DraggerLayer 调用本组件的拖拽协议完成。
##
## 依赖：
## CardZone：提供区域基础协议。
## CardInstance：保存卡牌区域、位置与朝向状态。

extends CardZone
class_name HandZone

signal hand_count_changed(current_count: int, max_count: int)

var cards: Array[Card] = []

# 拖拽只保存当前预览卡与目标插入位置；稳定成员始终由 cards 表示。
var _preview_card: Card
var _preview_insert_index := -1

@export var display_capacity: int = 10
@export var card_overlap: float = 10.0
@export var card_row_y: float = 0.0
@export var rot_max: float = 8.0
@export_range(0.0, 1.0, 0.05) var rot_growth: float = 0.5
@export_group("Floating")
@export var float_amplitude: float = 4.0
@export var float_speed: float = 2.0
@export var float_phase_offset: float = 0.5

var _float_time: float = 0.0


func _ready() -> void:
	_register_existing_cards()
	refresh_hand()
	call_deferred("refresh_hand")


func _process(delta: float) -> void:
	if float_amplitude == 0.0 or cards.is_empty():
		return
	_float_time += delta * float_speed
	refresh_hand()


func _register_existing_cards() -> void:
	for child in get_children():
		if child is Card and not cards.has(child):
			cards.append(child)
			_normalize_hand_state(child)


func get_cards() -> Array[Card]:
	return cards.duplicate()


func get_card_count() -> int:
	return cards.size()


func get_display_capacity() -> int:
	return display_capacity


func owns_card(card: Card) -> bool:
	return card != null and cards.has(card)


func add_card(card: Card, keep_global_position: bool = true) -> bool:
	if card == null or card.get_card_inst() == null:
		return false

	var insert_index := _get_insert_index(card)
	return _accept_card(card, keep_global_position, insert_index)


func remove_card(card: Card) -> bool:
	var index := cards.find(card)
	if index == -1:
		return false

	cards.remove_at(index)
	_clear_preview()
	refresh_hand()
	_emit_hand_count_changed()
	return true


func can_trans_to_target(_card: Card) -> bool:
	return true


func can_trans_from_source(card: Card) -> bool:
	return owns_card(card)


# 来源 Zone：只从布局中暂时排除拖拽卡；稳定成员不变。
func start_drag(card: Card) -> void:
	if card == null or not cards.has(card):
		return

	_preview_card = card
	_preview_insert_index = -1
	refresh_hand()


# 目标 Zone：根据拖拽卡中心位置保存目标插入槽位。
func update_drag(card: Card) -> void:
	if card == null or not can_trans_to_target(card):
		return

	_preview_card = card
	var layout_count := cards.size() if not cards.has(card) else cards.size() - 1
	_preview_insert_index = clampi(
		_get_preview_insert_index(card, layout_count + 1),
		0,
		layout_count
	)
	refresh_hand()


func _get_preview_insert_index(card: Card, preview_count: int) -> int:
	if preview_count <= 0:
		return 0

	var card_width := _get_card_width(card)
	var step := maxf(0.0, card_width - card_overlap)
	var total_width := card_width + step * float(preview_count - 1)
	var start_x := (size.x - total_width) * 0.5
	var local_center_x := (get_global_transform_with_canvas().affine_inverse() * (card.global_position + card.size * 0.5)).x

	for index in range(preview_count):
		var slot_center_x := start_x + step * float(index) + card_width * 0.5
		if local_center_x < slot_center_x:
			return index
	return preview_count


func drag_end_source(card: Card, ok: bool) -> bool:
	if card == null or not cards.has(card):
		return false

	var keeps_same_zone_preview := (
		ok
		and card == _preview_card
		and _preview_insert_index >= 0
	)
	if ok:
		cards.erase(card)
		_emit_hand_count_changed()

	if not keeps_same_zone_preview:
		_clear_preview()
	refresh_hand()
	return true


func drag_end_target(card: Card, ok: bool) -> bool:
	if not ok:
		if card == _preview_card:
			_preview_insert_index = -1
			if not cards.has(card):
				_preview_card = null
			refresh_hand()
		return false

	if card == null:
		return false

	var insert_index := (
		_preview_insert_index
		if card == _preview_card and _preview_insert_index >= 0
		else _get_insert_index(card)
	)
	return _accept_card(card, true, insert_index)


func _accept_card(card: Card, keep_global_position: bool, insert_index: int) -> bool:
	if card == null or card.get_card_inst() == null:
		return false

	var was_logical_member := cards.has(card)
	var old_global := card.global_position
	var old_index := cards.find(card)
	if old_index != -1:
		cards.remove_at(old_index)
		if old_index < insert_index:
			insert_index -= 1

	if card.get_parent() == null:
		add_child(card)
	elif card.get_parent() != self:
		card.reparent(self, keep_global_position)
	if keep_global_position:
		card.global_position = old_global

	insert_index = clampi(insert_index, 0, cards.size())
	cards.insert(insert_index, card)
	_normalize_hand_state(card)
	_clear_preview()
	refresh_hand()
	if not was_logical_member:
		_emit_hand_count_changed()
	return true


func _emit_hand_count_changed() -> void:
	hand_count_changed.emit(get_card_count(), get_display_capacity())


func _normalize_hand_state(card: Card) -> void:
	var instance := card.get_card_inst()
	if instance == null:
		return
	var came_from_board := instance.cur_zone == CardInstance.ZONE.BOARD
	instance.cur_zone = CardInstance.ZONE.HAND
	instance.battlefield_pos = Vector2i(-1, -1)
	if came_from_board:
		instance.direction = 0
	card.rotation = 0.0
	card.refresh_display()



func _get_insert_index(card: Card) -> int:
	var card_center_x := card.global_position.x + card.size.x * 0.5
	for index in range(cards.size()):
		var current := cards[index]
		if not is_instance_valid(current) or current == card:
			continue

		var current_center_x := current.global_position.x + current.size.x * 0.5
		if current.get_parent() == self:
			current_center_x = (get_global_transform_with_canvas() * (current.target_position + current.size * 0.5)).x

		if card_center_x < current_center_x:
			return index
	return cards.size()


func refresh_hand() -> void:
	_prune_cards()
	var layout := _get_layout_cards()
	var count := layout.size()
	if count == 0:
		return

	var card_width := _get_card_width(_preview_card if is_instance_valid(_preview_card) else layout[0])
	var step := maxf(0.0, card_width - card_overlap)
	var total_width := card_width + step * float(count - 1)
	var start_x := (size.x - total_width) * 0.5
	var center_index := (count - 1) * 0.5
	var rotation_growth := minf(1.0, maxf(0.0, float(count - 1) * rot_growth))
	var side_rotation := deg_to_rad(rot_max) * rotation_growth

	for index in range(count):
		var card := layout[index]
		if card == null or not is_instance_valid(card):
			continue

		if card != _preview_card or not card.dragging:
			var float_offset := sin(_float_time + float(index) * float_phase_offset) * float_amplitude
			card.target_position = Vector2(start_x + step * float(index), card_row_y + float_offset)
			var normalized_distance := 0.0
			if center_index > 0.0:
				normalized_distance = (float(index) - center_index) / center_index
			card.rotation = normalized_distance * side_rotation
			card.z_index = index


func _get_layout_cards() -> Array[Card]:
	if _preview_card == null:
		return cards.duplicate()

	var result := cards.duplicate()
	result.erase(_preview_card)
	if _preview_insert_index >= 0:
		result.insert(
			clampi(_preview_insert_index, 0, result.size()),
			_preview_card
		)
	return result


func _get_card_width(card: Card) -> float:
	if card != null and is_instance_valid(card) and card.size.x > 0.0:
		return card.size.x
	for existing in cards:
		if is_instance_valid(existing) and existing.size.x > 0.0:
			return existing.size.x
	return 84.0


func _prune_cards() -> void:
	var valid_cards: Array[Card] = []
	for card in cards:
		if is_instance_valid(card):
			valid_cards.append(card)
	cards = valid_cards


func _clear_preview() -> void:
	_preview_card = null
	_preview_insert_index = -1

func name()->String:
	return "hand_zone"
