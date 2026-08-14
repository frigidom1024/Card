## 牌桌卡牌区域组件
##
## 负责管理 Card/CardInstance 模式下的牌桌卡牌空间与拖拽事务。
## 包括：
## - 牌链卡牌的稳定成员集合与二维格索引
## - ROOT、NORMAL、GUIDE 的放置校验和吸附布局
## - 拖拽开始、取消、同区移动以及跨区域拆链提交
## - 发布已提交的放置与拆链空间事实
##
## 不负责：
## - 卡牌数据的创建、持久化或购买规则
## - 手牌、商店、回收区等其它区域的管理
## - 事件格、战斗结算或返回手牌的业务决策
## - 跨区域拖拽来源解析与提交顺序
##
## 使用方式：
## 将 CardZone 注册到 DraggerLayer 后，通过 add_card() 或拖拽协议接收
## 已绑定 CardInstance 的 Card。Board 负责消费 card_placed 与
## chain_detached 信号并编排更高层业务。
##
## 依赖：
## Card：牌桌上的卡牌视图与交互组件。
## CardInstance：保存区域、格坐标和方向的唯一运行时状态源。

class_name BoardZone
extends CardZone

signal card_placed(
	card: Card,
	occupied_cells: Array[Vector2i],
	affected_cards: Array[Card],
	guide_resolved: bool
)
signal chain_detached(
	removed_card: Card,
	followers_to_return: Array[Card],
	original_chain_size: int
)

@export var preview_valid_color := Color(0.35, 0.85, 0.45, 0.32)
@export var preview_invalid_color := Color(0.95, 0.25, 0.25, 0.38)

@onready var back_ground: BoardZoneBG = $BackGround

var cards: Array[Card] = []
var _grid_owner: Dictionary = {}
var _drag_layer: DraggerLayer

var _preview_card: Card
var _preview_cells: Array[Vector2i] = []
var _preview_valid := false

var _drag_source_card: Card
var _drag_source_index := -1
var _drag_source_original_chain_size := 0
var _drag_source_direction := 0
var _drag_source_cells: Array[Vector2i] = []
var _drag_followers: Array[Card] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sync_layout()
	_register_existing_cards()


func _exit_tree() -> void:
	if _drag_layer != null and is_instance_valid(_drag_layer):
		_drag_layer.unregister_zone(self)


func _draw() -> void:
	if _preview_cells.is_empty() or back_ground == null:
		return
	var color := preview_valid_color if _preview_valid else preview_invalid_color
	for cell in _preview_cells:
		var cell_origin := back_ground.position + Vector2(cell) * back_ground.cell_size
		draw_rect(Rect2(cell_origin, Vector2.ONE * back_ground.cell_size), color, true)


func set_drag_layer(value: DraggerLayer) -> void:
	if _drag_layer != null and is_instance_valid(_drag_layer):
		_drag_layer.unregister_zone(self)
	_drag_layer = value
	if _drag_layer != null:
		_drag_layer.register_zone(self)
	for card: Card in cards:
		if is_instance_valid(card):
			card.bind_drag_layer(_drag_layer)


func sync_layout() -> void:
	if not is_node_ready() or back_ground == null:
		return
	back_ground.cell_size = maxf(back_ground.cell_size, 1.0)
	back_ground.grid_width = maxi(back_ground.grid_width, 1)
	back_ground.grid_height = maxi(back_ground.grid_height, 1)
	back_ground.configure(
		Vector2(back_ground.grid_width, back_ground.grid_height) * back_ground.cell_size,
		back_ground.cell_size,
		back_ground.grid_width,
		back_ground.grid_height
	)


func owns_card(card: Card) -> bool:
	_prune_cards()
	return card != null and cards.has(card)


func add_card(card: Card, keep_global_position: bool = true) -> bool:
	if not _is_valid_bound_card(card):
		return false

	var cells := _candidate_cells(card)
	if _is_guide_card(card):
		if not _can_place_guide(cells):
			return false
		_commit_guide_layout(card, cells)
		_clear_preview()
		return true

	var existing_index := cards.find(card)
	var excluded_card := card if existing_index != -1 else null
	if not _can_place_cells(card, cells, excluded_card):
		return false
	if existing_index == -1:
		_reparent_card(card, keep_global_position)
		cards.append(card)
	else:
		_release_card_cells(card)
	_commit_card_layout(card, cells)
	_clear_preview()
	return true


func remove_card(card: Card) -> bool:
	var index := cards.find(card)
	if index == -1:
		return false
	_release_card_cells(card)
	cards.remove_at(index)
	var card_inst := card.get_card_inst()
	if card_inst != null:
		card_inst.battlefield_pos = Vector2i(-1, -1)
		card.refresh_display()
	_reindex_cards()
	_clear_preview()
	return true


func get_cards() -> Array[Card]:
	_prune_cards()
	return cards.duplicate()


func clear_cards(queue_free_cards: bool = false) -> void:
	for card: Card in cards.duplicate():
		if not is_instance_valid(card):
			continue
		_release_card_cells(card)
		var card_inst := card.get_card_inst()
		if card_inst != null:
			card_inst.battlefield_pos = Vector2i(-1, -1)
			card_inst.direction = 0
			card.refresh_display()
		if queue_free_cards:
			card.queue_free()
	cards.clear()
	_grid_owner.clear()
	_clear_drag_source()
	_clear_preview()


func get_card_cells(card: Card) -> Array[Vector2i]:
	if not _is_valid_bound_card(card):
		return []
	var stored := _stored_cells(card)
	return stored if not stored.is_empty() else _candidate_cells(card)


func get_card_at(cell: Vector2i) -> Card:
	var owner = _grid_owner.get(cell, null)
	if owner == null or not is_instance_valid(owner):
		return null
	if owner is Card:
		return owner as Card
	return null


func get_placement_cell(card: Card) -> Vector2i:
	if not _is_valid_bound_card(card):
		return Vector2i(-1, -1)

	var cells := _stored_cells(card)
	if cells.is_empty():
		cells = _candidate_cells(card)
	if cells.size() != 2:
		return Vector2i(-1, -1)

	var direction := _card_direction(card)
	var forward_cell: Vector2i
	match direction:
		0:
			forward_cell = cells[0]
		1:
			forward_cell = cells[1]
		2:
			forward_cell = cells[1]
		3:
			forward_cell = cells[0]
		_:
			return Vector2i(-1, -1)

	const OFFSETS: Array[Vector2i] = [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]
	return forward_cell + OFFSETS[direction]


func can_place_card(card: Card, exclude_card: Card = null) -> bool:
	if not _is_valid_bound_card(card):
		return false
	var cells := _candidate_cells(card)
	if _is_guide_card(card):
		return _can_place_guide(cells)
	return _can_place_cells(card, cells, exclude_card)


func get_combat_card_chain() -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	for card: Card in cards:
		if not is_instance_valid(card):
			continue
		var card_inst := card.get_card_inst()
		if card_inst != null:
			result.append(card_inst)
	return result


func start_drag(card: Card) -> void:
	var index := cards.find(card)
	if index == -1 or not _is_valid_bound_card(card) or _drag_source_card != null:
		return

	_drag_source_card = card
	_drag_source_index = index
	_drag_source_original_chain_size = cards.size()
	var card_inst := card.get_card_inst()
	_drag_source_direction = card_inst.direction
	_drag_source_cells = _stored_cells(card)
	if _drag_source_cells.is_empty():
		_drag_source_cells = _candidate_cells(card)
	_drag_followers.clear()
	for follower_index in range(index + 1, cards.size()):
		_drag_followers.append(cards[follower_index])

	# 拖拽期间保留稳定成员和原格占用；只有成功提交后才释放来源状态。
	_clear_preview()


func update_drag(card: Card) -> void:
	if not _is_valid_bound_card(card):
		_clear_preview()
		return
	_preview_card = card
	_preview_cells = _candidate_cells(card)
	_preview_valid = can_trans_to_target(card)
	queue_redraw()


func can_trans_to_target(card: Card) -> bool:
	if not _is_valid_bound_card(card):
		return false
	var cells := _candidate_cells(card)
	if _is_guide_card(card):
		return _can_place_guide(cells)

	var source_index := cards.find(card)
	if _drag_source_card == card:
		# BoardZone 只允许链尾在同区移动；校验时忽略它自己的原格占用。
		if _drag_source_index != _drag_source_original_chain_size - 1:
			return false
		return _can_place_cells(card, cells, card)
	if source_index != -1 and source_index != cards.size() - 1:
		return false
	return _can_place_cells(card, cells, card if source_index != -1 else null)


func can_trans_from_source(card: Card) -> bool:
	return owns_card(card) and _is_valid_bound_card(card)


func drag_end_source(card: Card, ok: bool) -> bool:
	if not ok:
		_restore_drag_source()
		_clear_drag_source()
		_clear_preview()
		return true

	var is_same_zone_move := (
		_preview_card == card
		and _preview_valid
		and _drag_source_index == _drag_source_original_chain_size - 1
	)
	_release_card_cells(card)
	cards.erase(card)
	var card_inst := card.get_card_inst()
	if card_inst != null:
		card_inst.battlefield_pos = Vector2i(-1, -1)
		# 保留 BOARD，使目标 Zone 能识别来源并按自身规则完成状态迁移。
		card_inst.cur_zone = CardInstance.ZONE.BOARD
		card.refresh_display()

	if not is_same_zone_move:
		var followers_to_return := _detach_followers()
		chain_detached.emit(card, followers_to_return, _drag_source_original_chain_size)

	_clear_drag_source()
	_clear_preview()
	_reindex_cards()
	return true


func drag_end_target(card: Card, ok: bool) -> bool:
	if not ok:
		_clear_preview()
		return true

	var cells := _candidate_cells(card)
	if _is_guide_card(card):
		_commit_guide_layout(card, cells)
		_clear_preview()
		return true

	var existing_index := cards.find(card)
	if existing_index == -1:
		_reparent_card(card, true)
		cards.append(card)
	else:
		_release_card_cells(card)
	_commit_card_layout(card, cells)
	_clear_preview()
	return true


func _register_existing_cards() -> void:
	var existing_cards: Array[Card] = []
	for child in get_children():
		if child is Card:
			existing_cards.append(child as Card)
	for card in existing_cards:
		if not cards.has(card):
			add_card(card, true)


func _is_valid_bound_card(card: Card) -> bool:
	return (
		card != null
		and is_instance_valid(card)
		and card.get_card_inst() != null
		and card.get_card_inst().card_data != null
	)


func _get_card_global_center(card: Card) -> Vector2:
	return card.get_global_transform_with_canvas() * (card.size * 0.5)


func _card_direction(card: Card) -> int:
	var card_inst := card.get_card_inst()
	return posmod(card_inst.direction, 4) if card_inst != null else 0


func _candidate_cells(card: Card) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if back_ground == null or back_ground.cell_size <= 0.0:
		return result

	var local_center := back_ground.to_local(_get_card_global_center(card))
	var direction := _card_direction(card)
	var anchor: Vector2i
	if direction % 2 == 0:
		anchor = Vector2i(
			roundi(local_center.x / back_ground.cell_size - 0.5),
			roundi(local_center.y / back_ground.cell_size - 1.0)
		)
		result.append(anchor)
		result.append(anchor + Vector2i(0, 1))
	else:
		anchor = Vector2i(
			roundi(local_center.x / back_ground.cell_size - 1.0),
			roundi(local_center.y / back_ground.cell_size - 0.5)
		)
		result.append(anchor)
		result.append(anchor + Vector2i(1, 0))
	return result


func _stored_cells(card: Card) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _grid_owner:
		var owner = _grid_owner[cell]
		if owner == card:
			result.append(cell as Vector2i)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result


func _can_place_cells(card: Card, cells: Array[Vector2i], exclude_card: Card = null) -> bool:
	if cells.size() != 2 or not _are_cells_in_bounds(cells) or _has_conflict(cells, exclude_card):
		return false

	var existing_index := cards.find(card)
	if existing_index != -1:
		if existing_index != cards.size() - 1:
			return false
		if existing_index == 0:
			return _is_root_card(card)
		return get_placement_cell(cards[existing_index - 1]) in cells

	if cards.is_empty():
		return _is_root_card(card)
	if _is_root_card(card):
		return false
	return get_placement_cell(cards.back()) in cells


func _can_place_guide(cells: Array[Vector2i]) -> bool:
	if cards.is_empty() or cells.size() != 2:
		return false
	if not _are_cells_in_bounds(cells) or _has_conflict(cells):
		return false
	return get_placement_cell(cards.back()) in cells


func _are_cells_in_bounds(cells: Array[Vector2i]) -> bool:
	if back_ground == null:
		return false
	for cell in cells:
		if (
			cell.x < 0
			or cell.x >= back_ground.grid_width
			or cell.y < 0
			or cell.y >= back_ground.grid_height
		):
			return false
	return true


func _has_conflict(cells: Array[Vector2i], exclude_card: Card = null) -> bool:
	for cell in cells:
		var owner := get_card_at(cell)
		if owner != null and owner != exclude_card:
			return true
	return false


func _is_root_card(card: Card) -> bool:
	var card_inst := card.get_card_inst()
	return (
		card_inst != null
		and card_inst.card_data != null
		and card_inst.card_data.card_type == CardData.CardType.ROOT
	)


func _is_guide_card(card: Card) -> bool:
	var card_inst := card.get_card_inst()
	return (
		card_inst != null
		and card_inst.card_data != null
		and card_inst.card_data.card_type == CardData.CardType.GUIDE
	)


func _commit_card_layout(card: Card, cells: Array[Vector2i]) -> void:
	_release_card_cells(card)
	for cell in cells:
		_grid_owner[cell] = card
	_snap_card_to_cells(card, cells)
	card.bind_drag_layer(_drag_layer)
	card.z_index = cards.find(card)

	var card_inst := card.get_card_inst()
	card_inst.cur_zone = CardInstance.ZONE.BOARD
	card_inst.battlefield_pos = _placement_origin_for(cells)
	card.refresh_display()
	_reindex_cards()

	var affected_cards: Array[Card] = [card]
	card_placed.emit(card, cells.duplicate(), affected_cards, false)


func _commit_guide_layout(card: Card, guide_cells: Array[Vector2i]) -> void:
	if not _can_place_guide(guide_cells):
		return

	# GUIDE 只提供牌链尾部的新格子与方向，不进入 BoardZone。
	# 牌链布局完全由原有格子和 CardInstance.direction 重建，避免复制跨父节点坐标。
	var previous_cells: Array[Array] = []
	var previous_directions: Array[int] = []
	for chain_card: Card in cards:
		var cells := _stored_cells(chain_card)
		if cells.is_empty():
			cells = _candidate_cells(chain_card)
		previous_cells.append(cells.duplicate())
		previous_directions.append(_card_direction(chain_card))

	var guide_direction := _card_direction(card)
	_grid_owner.clear()
	for index in range(cards.size()):
		var chain_card := cards[index]
		var target_cells: Array[Vector2i]
		var target_direction: int
		if index == cards.size() - 1:
			target_cells = guide_cells
			target_direction = guide_direction
		else:
			target_cells.assign(previous_cells[index + 1])
			target_direction = previous_directions[index + 1]

		var instance := chain_card.get_card_inst()
		instance.direction = target_direction
		instance.cur_zone = CardInstance.ZONE.BOARD
		instance.battlefield_pos = _placement_origin_for(target_cells)
		_snap_card_to_cells(chain_card, target_cells)
		chain_card.bind_drag_layer(_drag_layer)
		chain_card.z_index = index
		chain_card.refresh_display()
		for cell in target_cells:
			_grid_owner[cell] = chain_card

	card_placed.emit(card, guide_cells.duplicate(), cards.duplicate(), true)


func _snap_card_to_cells(card: Card, cells: Array[Vector2i]) -> void:
	var snapped_center := Vector2.ZERO
	for cell in cells:
		snapped_center += back_ground.to_global((Vector2(cell) + Vector2(0.5, 0.5)) * back_ground.cell_size)
	snapped_center /= float(cells.size())
	card.global_position = snapped_center - card.size * 0.5
	card.target_position = card.position
	card.rotation = deg_to_rad(float(_card_direction(card) * 90))


func _placement_origin_for(cells: Array[Vector2i]) -> Vector2i:
	return cells[0] if not cells.is_empty() else Vector2i(-1, -1)


func _reparent_card(card: Card, keep_global_position: bool) -> void:
	if card.get_parent() == null:
		add_child(card)
	elif card.get_parent() != self:
		card.reparent(self, keep_global_position)


func _release_card_cells(card: Card) -> void:
	for cell in _grid_owner.keys().duplicate():
		if _grid_owner[cell] == card:
			_grid_owner.erase(cell)


func _detach_followers() -> Array[Card]:
	var result: Array[Card] = []
	for follower: Card in _drag_followers:
		if not is_instance_valid(follower):
			continue
		if cards.has(follower):
			_release_card_cells(follower)
			cards.erase(follower)
		var instance := follower.get_card_inst()
		if instance != null:
			instance.battlefield_pos = Vector2i(-1, -1)
			# 保留 BOARD，使 HandZone 能识别来自牌桌并清理方向。
			instance.cur_zone = CardInstance.ZONE.BOARD
			follower.refresh_display()
		result.append(follower)
	return result


func _restore_drag_source() -> void:
	if not is_instance_valid(_drag_source_card):
		return
	var card := _drag_source_card
	if card.get_parent() != self:
		_reparent_card(card, true)
	if not cards.has(card):
		cards.insert(clampi(_drag_source_index, 0, cards.size()), card)

	var card_inst := card.get_card_inst()
	if card_inst != null:
		card_inst.cur_zone = CardInstance.ZONE.BOARD
		card_inst.direction = _drag_source_direction
		card_inst.battlefield_pos = _placement_origin_for(_drag_source_cells)
		card.refresh_display()
	for cell in _drag_source_cells:
		_grid_owner[cell] = card
	if not _drag_source_cells.is_empty():
		_snap_card_to_cells(card, _drag_source_cells)
	card.bind_drag_layer(_drag_layer)
	_reindex_cards()


func _reindex_cards() -> void:
	for index in range(cards.size()):
		var card := cards[index]
		if is_instance_valid(card):
			card.z_index = index


func _prune_cards() -> void:
	var valid_cards: Array[Card] = []
	for card: Card in cards:
		if is_instance_valid(card):
			valid_cards.append(card)
	cards = valid_cards
	for cell in _grid_owner.keys().duplicate():
		var owner = _grid_owner[cell]
		if owner == null or not is_instance_valid(owner):
			_grid_owner.erase(cell)


func _clear_preview() -> void:
	_preview_card = null
	_preview_cells.clear()
	_preview_valid = false
	queue_redraw()


func _clear_drag_source() -> void:
	_drag_source_card = null
	_drag_source_index = -1
	_drag_source_original_chain_size = 0
	_drag_source_direction = 0
	_drag_source_cells.clear()
	_drag_followers.clear()

func name()->String:
	return "board_zone"
