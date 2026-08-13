class_name BoardZone
extends CardZone

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
var _drag_source_global_position := Vector2.ZERO
var _drag_source_target_position := Vector2.ZERO
var _drag_source_rotation := 0.0
var _drag_source_direction := 0
var _drag_source_battlefield_pos := Vector2i(-1, -1)
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


func add_card(card: Card, keep_global_position: bool = true) -> bool:
	if not _is_valid_bound_card(card):
		return false

	var cells := _candidate_cells(card)
	if not _can_place_cells(card, cells, card if cards.has(card) else null):
		return false

	var existing_index := cards.find(card)
	if existing_index == -1:
		if card.get_parent() == null:
			add_child(card)
		elif card.get_parent() != self:
			card.reparent(self, keep_global_position)
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
	if card.cur_zone == self:
		card.cur_zone = null
	var card_inst := card.get_card_inst()
	if card_inst != null:
		card_inst.battlefield_pos = Vector2i(-1, -1)
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
		if card.cur_zone == self:
			card.cur_zone = null
		var card_inst := card.get_card_inst()
		if card_inst != null:
			card_inst.battlefield_pos = Vector2i(-1, -1)
			card_inst.direction = 0
		if queue_free_cards:
			card.queue_free()
	cards.clear()
	_grid_owner.clear()
	_clear_drag_snapshot()
	_clear_preview()


func get_card_cells(card: Card) -> Array[Vector2i]:
	if not _is_valid_bound_card(card):
		return []
	return _candidate_cells(card)


func get_card_at(cell: Vector2i) -> Card:
	var owner = _grid_owner.get(cell)
	return owner as Card if owner is Card and is_instance_valid(owner) else null


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
	return _can_place_cells(card, _candidate_cells(card), exclude_card)


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
	if index == -1 or not _is_valid_bound_card(card):
		return

	_drag_source_card = card
	_drag_source_index = index
	_drag_source_global_position = card.global_position
	_drag_source_target_position = card.target_position
	_drag_source_rotation = card.rotation
	var card_inst := card.get_card_inst()
	_drag_source_direction = card_inst.direction
	_drag_source_battlefield_pos = card_inst.battlefield_pos
	_drag_followers.clear()
	for follower_index in range(index + 1, cards.size()):
		_drag_followers.append(cards[follower_index])
	_clear_preview()


func update_drag(card: Card) -> void:
	if not _is_valid_bound_card(card):
		_clear_preview()
		return
	_preview_card = card
	_preview_cells = _candidate_cells(card)
	_preview_valid = _can_place_cells(card, _preview_cells, card if cards.has(card) else null)
	queue_redraw()


func can_trans_to_target(card: Card) -> bool:
	if not _is_valid_bound_card(card):
		return false
	var source_index := cards.find(card)
	if source_index != -1 and source_index != cards.size() - 1:
		return false
	return _can_place_cells(card, _candidate_cells(card), card if source_index != -1 else null)


func can_trans_from_source(card: Card) -> bool:
	return cards.has(card) and _is_valid_bound_card(card)


func drag_end_source(card: Card, ok: bool) -> bool:
	if card != _drag_source_card or _drag_source_index < 0:
		return false

	if not ok:
		_restore_drag_source()
		_clear_drag_snapshot()
		_clear_preview()
		return true

	var destination := card.cur_zone
	if destination is HandZone:
		_return_dragged_segment_to_hand(destination as HandZone)
	else:
		_remove_dragged_card_from_board(card)

	_clear_drag_snapshot()
	_clear_preview()
	return true


func drag_end_target(card: Card, ok: bool) -> bool:
	if not ok:
		_clear_preview()
		return false
	if not can_trans_to_target(card):
		_clear_preview()
		return false

	var cells := _candidate_cells(card)
	var existing_index := cards.find(card)
	if existing_index == -1:
		if card.get_parent() == null:
			add_child(card)
		elif card.get_parent() != self:
			card.reparent(self, true)
		cards.append(card)
	else:
		_release_card_cells(card)

	_commit_card_layout(card, cells)
	_clear_drag_snapshot()
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
		if _grid_owner[cell] == card:
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


func _are_cells_in_bounds(cells: Array[Vector2i]) -> bool:
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


func _commit_card_layout(card: Card, cells: Array[Vector2i]) -> void:
	for cell in cells:
		_grid_owner[cell] = card

	var snapped_center := Vector2.ZERO
	for cell in cells:
		snapped_center += back_ground.to_global((Vector2(cell) + Vector2(0.5, 0.5)) * back_ground.cell_size)
	snapped_center /= float(cells.size())
	card.global_position = snapped_center - card.size * 0.5
	card.target_position = card.position
	card.rotation = deg_to_rad(float(_card_direction(card) * 90))
	card.cur_zone = self
	card.bind_drag_layer(_drag_layer)
	card.z_index = cards.find(card)

	var card_inst := card.get_card_inst()
	card_inst.cur_zone = CardInstance.ZONE.BOARD
	card_inst.battlefield_pos = cells[0]


func _release_card_cells(card: Card) -> void:
	for cell in _grid_owner.keys():
		if _grid_owner[cell] == card:
			_grid_owner.erase(cell)


func _remove_dragged_card_from_board(card: Card) -> void:
	_release_card_cells(card)
	cards.erase(card)
	var card_inst := card.get_card_inst()
	if card_inst != null:
		card_inst.battlefield_pos = Vector2i(-1, -1)


func _return_dragged_segment_to_hand(hand_zone: HandZone) -> void:
	var segment: Array[Card] = []
	if is_instance_valid(_drag_source_card):
		segment.append(_drag_source_card)
	for follower: Card in _drag_followers:
		if is_instance_valid(follower):
			segment.append(follower)

	for segment_card: Card in segment:
		_release_card_cells(segment_card)
		cards.erase(segment_card)
		var card_inst := segment_card.get_card_inst()
		if card_inst != null:
			card_inst.cur_zone = CardInstance.ZONE.HAND
			card_inst.battlefield_pos = Vector2i(-1, -1)
			card_inst.direction = 0
		segment_card.rotation = 0.0
		segment_card.bind_drag_layer(_drag_layer)

	for follower: Card in _drag_followers:
		if is_instance_valid(follower):
			hand_zone.add_card(follower, true)


func _restore_drag_source() -> void:
	if not is_instance_valid(_drag_source_card):
		return
	_drag_source_card.global_position = _drag_source_global_position
	_drag_source_card.target_position = _drag_source_target_position
	_drag_source_card.rotation = _drag_source_rotation
	var card_inst := _drag_source_card.get_card_inst()
	if card_inst != null:
		card_inst.cur_zone = CardInstance.ZONE.BOARD
		card_inst.direction = _drag_source_direction
		card_inst.battlefield_pos = _drag_source_battlefield_pos


func _prune_cards() -> void:
	var valid_cards: Array[Card] = []
	for card: Card in cards:
		if is_instance_valid(card):
			valid_cards.append(card)
	cards = valid_cards
	for cell in _grid_owner.keys():
		if not is_instance_valid(_grid_owner[cell]):
			_grid_owner.erase(cell)


func _clear_preview() -> void:
	_preview_card = null
	_preview_cells.clear()
	_preview_valid = false
	queue_redraw()


func _clear_drag_snapshot() -> void:
	_drag_source_card = null
	_drag_source_index = -1
	_drag_source_global_position = Vector2.ZERO
	_drag_source_target_position = Vector2.ZERO
	_drag_source_rotation = 0.0
	_drag_source_direction = 0
	_drag_source_battlefield_pos = Vector2i(-1, -1)
	_drag_followers.clear()
