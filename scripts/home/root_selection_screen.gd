class_name RootSelectionScreen
extends Control

signal back_requested
signal exploration_requested(preset: StartingDeckData)

const CARD_SCENE := preload("res://scenes/card/card.tscn")

const ROOT_CARD_SCALE := 2.05
const STARTER_CARD_SCALE := 1.05
const CARD_SIZE := Vector2(104.0, 185.0)
const STARTER_CARD_SPACING := 122.0
const STARTER_SCATTER_X := 6.0
const STARTER_SCATTER_Y_MIN := 3.0
const STARTER_SCATTER_Y_MAX := 10.0
const STARTER_SCATTER_ROTATION_MIN := 1.0
const STARTER_SCATTER_ROTATION_MAX := 5.0


@onready var _back_button: Button = $SafeArea/SelectionFrame/FrameMargin/ContentLayout/Header/BackButton
@onready var _deck_name_label: Label = $SafeArea/SelectionFrame/FrameMargin/ContentLayout/MainArea/DeckNameLabel
@onready var _previous_deck_button: Button = $SafeArea/SelectionFrame/FrameMargin/ContentLayout/MainArea/DeckCarousel/PreviousDeckButton
@onready var _root_preview_slot: Control = $SafeArea/SelectionFrame/FrameMargin/ContentLayout/MainArea/DeckCarousel/RootPreviewSlot
@onready var _next_deck_button: Button = $SafeArea/SelectionFrame/FrameMargin/ContentLayout/MainArea/DeckCarousel/NextDeckButton
@onready var _remaining_starter_preview_row: Control = $SafeArea/SelectionFrame/FrameMargin/ContentLayout/MainArea/RemainingStarterCardPreviewRow
@onready var _unlock_hint_label: Label = $SafeArea/SelectionFrame/FrameMargin/ContentLayout/Footer/UnlockHintLabel
@onready var _start_exploration_button: Button = $SafeArea/SelectionFrame/FrameMargin/ContentLayout/Footer/StartRow/StartExplorationButton

var selected_preset: StartingDeckData

var _configured_presets: Array[StartingDeckData] = []
var _available_presets: Array[StartingDeckData] = []
var _selected_index := -1
var _exploration_requested := false
var _preview_position_refresh_queued := false


func configure(presets: Array[StartingDeckData]) -> void:
	_configured_presets = presets.duplicate()
	if is_node_ready():
		_rebuild_presets()


func _ready() -> void:
	_connect_button(_back_button, _on_back_pressed)
	_connect_button(_previous_deck_button, _on_previous_deck_pressed)
	_connect_button(_next_deck_button, _on_next_deck_pressed)
	_connect_button(_start_exploration_button, _on_start_exploration_pressed)

	if not _root_preview_slot.resized.is_connected(_queue_preview_position_refresh):
		_root_preview_slot.resized.connect(_queue_preview_position_refresh)
	if not _remaining_starter_preview_row.resized.is_connected(_queue_preview_position_refresh):
		_remaining_starter_preview_row.resized.connect(_queue_preview_position_refresh)

	_rebuild_presets()


func _connect_button(button: Button, callback: Callable) -> void:
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _rebuild_presets() -> void:
	if not is_node_ready():
		return

	_available_presets.clear()
	selected_preset = null
	_selected_index = -1
	_exploration_requested = false

	var unlocked_root_ids := {}
	for preset in _configured_presets:
		if preset == null or not preset.validate().is_empty():
			continue

		var root_card := preset.get_root_card()
		if preset.is_unlocked:
			if unlocked_root_ids.has(root_card.card_id):
				continue
			unlocked_root_ids[root_card.card_id] = true
		_available_presets.append(preset)

	for index in _available_presets.size():
		if _available_presets[index].is_unlocked:
			_selected_index = index
			break
	if _selected_index < 0 and not _available_presets.is_empty():
		_selected_index = 0

	if _selected_index >= 0:
		selected_preset = _available_presets[_selected_index]
	_refresh_selection()


func _select_preset(preset: StartingDeckData) -> void:
	var preset_index := _available_presets.find(preset)
	if preset_index < 0:
		return
	_selected_index = preset_index
	selected_preset = preset
	_refresh_selection()


func _select_relative(offset: int) -> void:
	if _available_presets.size() <= 1:
		return
	_selected_index = posmod(_selected_index + offset, _available_presets.size())
	_select_preset(_available_presets[_selected_index])


func _refresh_selection() -> void:
	if not is_node_ready():
		return

	var can_cycle := _available_presets.size() > 1
	_previous_deck_button.disabled = not can_cycle
	_next_deck_button.disabled = not can_cycle
	_deck_name_label.text = selected_preset.display_name if selected_preset != null else "NO DECK AVAILABLE"

	var is_locked := selected_preset != null and not selected_preset.is_unlocked
	_start_exploration_button.disabled = selected_preset == null or is_locked or _exploration_requested
	_unlock_hint_label.text = (
		"THIS DECK IS LOCKED. COMPLETE MORE EXPEDITIONS TO UNLOCK IT."
		if is_locked
		else ""
	)
	_refresh_previews()


func _refresh_previews() -> void:
	_clear_preview_container(_root_preview_slot)
	_clear_preview_container(_remaining_starter_preview_row)
	if selected_preset == null:
		return

	_add_preview(_root_preview_slot, selected_preset.get_root_card(), ROOT_CARD_SCALE)
	for card_data in selected_preset.get_remaining_starter_cards():
		_add_preview(_remaining_starter_preview_row, card_data, STARTER_CARD_SCALE)
	_queue_preview_position_refresh()


func _clear_preview_container(container: Control) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_preview(parent: Control, card_data: CardData, preview_scale: float) -> Card:
	var card := CARD_SCENE.instantiate() as Card
	card.draggable = false
	card.focus_mode = Control.FOCUS_NONE
	card.scale = Vector2.ONE * preview_scale
	card.bind_card_inst(CardInstance.new(card_data))
	parent.add_child(card)
	return card


func _queue_preview_position_refresh() -> void:
	if _preview_position_refresh_queued or not is_inside_tree():
		return
	_preview_position_refresh_queued = true
	_refresh_preview_positions_after_layout()


func _refresh_preview_positions_after_layout() -> void:
	await get_tree().process_frame
	_preview_position_refresh_queued = false
	_refresh_preview_positions()


func _refresh_preview_positions() -> void:
	if not is_node_ready():
		return

	for child in _root_preview_slot.get_children():
		var card := child as Card
		if card == null:
			continue
		card.position = (_root_preview_slot.size - CARD_SIZE) * 0.5
		card.target_position = card.position
		card.velocity = Vector2.ZERO

	var previews := _remaining_starter_preview_row.get_children()
	var total_width := 0.0
	if not previews.is_empty():
		total_width = CARD_SIZE.x + float(previews.size() - 1) * STARTER_CARD_SPACING
	var start_x := (_remaining_starter_preview_row.size.x - total_width) * 0.5
	var scatter_rng := RandomNumberGenerator.new()
	var scatter_seed_source := ""
	if selected_preset != null:
		scatter_seed_source = str(selected_preset.get_root_card().card_id)
	scatter_rng.seed = hash(scatter_seed_source)
	for index in previews.size():
		var card := previews[index] as Card
		if card == null:
			continue
		var vertical_direction := -1.0 if index % 2 == 0 else 1.0
		var rotation_direction := -1.0 if scatter_rng.randi_range(0, 1) == 0 else 1.0
		var scatter_offset := Vector2(
			scatter_rng.randf_range(-STARTER_SCATTER_X, STARTER_SCATTER_X),
			vertical_direction * scatter_rng.randf_range(STARTER_SCATTER_Y_MIN, STARTER_SCATTER_Y_MAX),
		)
		card.position = Vector2(
			start_x + float(index) * STARTER_CARD_SPACING,
			(_remaining_starter_preview_row.size.y - CARD_SIZE.y) * 0.5,
		) + scatter_offset
		card.rotation_degrees = rotation_direction * scatter_rng.randf_range(
			STARTER_SCATTER_ROTATION_MIN,
			STARTER_SCATTER_ROTATION_MAX,
		)
		card.target_position = card.position
		card.velocity = Vector2.ZERO


func _on_previous_deck_pressed() -> void:
	_select_relative(-1)


func _on_next_deck_pressed() -> void:
	_select_relative(1)


func _on_back_pressed() -> void:
	back_requested.emit()


func _on_start_exploration_pressed() -> void:
	if _exploration_requested or selected_preset == null or not selected_preset.is_unlocked:
		return

	_exploration_requested = true
	_start_exploration_button.disabled = true
	exploration_requested.emit(selected_preset)
