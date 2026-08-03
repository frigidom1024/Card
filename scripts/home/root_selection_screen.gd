class_name RootSelectionScreen
extends Control

signal back_requested
signal exploration_requested(preset: StartingDeckData)

const CARD_ENTITY_SCENE := preload("res://scenes/card_view/card_entity.tscn")
const ROOT_OPTION_ENTRY_SCENE := preload("res://scenes/home/root_option_entry.tscn")

@onready var _back_button: Button = $SafeArea/Content/ContentLayout/Header/BackButton
@onready var _root_option_list: VBoxContainer = $SafeArea/Content/ContentLayout/MainArea/ChoicePanel/ChoiceLayout/RootOptionList
@onready var _root_preview_slot: Control = $SafeArea/Content/ContentLayout/MainArea/PreviewPanel/PreviewLayout/RootPreviewSlot
@onready var _remaining_starter_preview_row: Control = $SafeArea/Content/ContentLayout/MainArea/PreviewPanel/PreviewLayout/RemainingStarterCardPreviewRow
@onready var _unlock_hint_label: Label = $SafeArea/Content/ContentLayout/Footer/UnlockHintLabel
@onready var _start_exploration_button: Button = $SafeArea/Content/ContentLayout/Footer/FooterActions/StartExplorationButton
@onready var _main_area: BoxContainer = $SafeArea/Content/ContentLayout/MainArea

var selected_preset: StartingDeckData

var _configured_presets: Array[StartingDeckData] = []
var _entries_by_preset: Dictionary = {}
var _exploration_requested := false
var _preview_position_refresh_queued := false


func configure(presets: Array[StartingDeckData]) -> void:
	_configured_presets = presets.duplicate()
	if is_node_ready():
		_rebuild_options()


func _ready() -> void:
	if not _back_button.pressed.is_connected(_on_back_pressed):
		_back_button.pressed.connect(_on_back_pressed)
	if not _start_exploration_button.pressed.is_connected(_on_start_exploration_pressed):
		_start_exploration_button.pressed.connect(_on_start_exploration_pressed)
	if not _root_preview_slot.resized.is_connected(_queue_preview_position_refresh):
		_root_preview_slot.resized.connect(_queue_preview_position_refresh)
	if not _remaining_starter_preview_row.resized.is_connected(_queue_preview_position_refresh):
		_remaining_starter_preview_row.resized.connect(_queue_preview_position_refresh)

	var viewport := get_viewport()
	if not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)
	_apply_responsive_layout(viewport.get_visible_rect().size)
	_rebuild_options()


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.disconnect(_on_viewport_size_changed)


func _rebuild_options() -> void:
	if not is_node_ready():
		return

	for child in _root_option_list.get_children():
		child.queue_free()
	_entries_by_preset.clear()
	selected_preset = null
	_unlock_hint_label.text = ""
	_exploration_requested = false
	_start_exploration_button.disabled = true

	var unlocked_root_ids := {}
	for preset in _configured_presets:
		if preset == null:
			continue

		var validation_errors := preset.validate()
		if not validation_errors.is_empty():
			continue

		var root_card := preset.get_root_card()
		if preset.is_unlocked:
			if unlocked_root_ids.has(root_card.card_id):
				continue
			unlocked_root_ids[root_card.card_id] = true

		var entry := ROOT_OPTION_ENTRY_SCENE.instantiate() as RootOptionEntry
		entry.configure(preset)
		entry.pressed.connect(_on_root_option_pressed)
		_root_option_list.add_child(entry)
		_entries_by_preset[preset] = entry

		if selected_preset == null and preset.is_unlocked:
			_select_preset(preset)

	_refresh_selection_ui()
	_refresh_previews()


func _entry_for_preset(preset: StartingDeckData) -> RootOptionEntry:
	return _entries_by_preset.get(preset) as RootOptionEntry


func _on_root_option_pressed(entry: RootOptionEntry) -> void:
	if entry == null or entry.preset == null:
		return
	if entry.is_locked:
		_unlock_hint_label.text = "THIS ROOT IS LOCKED. COMPLETE MORE EXPEDITIONS TO UNLOCK IT."
		_refresh_selection_ui()
		return

	_select_preset(entry.preset)


func _select_preset(preset: StartingDeckData) -> void:
	selected_preset = preset
	_unlock_hint_label.text = ""
	_start_exploration_button.disabled = selected_preset == null
	_refresh_selection_ui()
	_refresh_previews()


func _refresh_selection_ui() -> void:
	if not is_node_ready():
		return
	for entry in _entries_by_preset.values():
		(entry as RootOptionEntry).set_selected((entry as RootOptionEntry).preset == selected_preset)


func _refresh_previews() -> void:
	if not is_node_ready():
		return
	_clear_preview_container(_root_preview_slot)
	_clear_preview_container(_remaining_starter_preview_row)
	if selected_preset == null:
		return

	_add_preview(_root_preview_slot, selected_preset.get_root_card())
	for card_data in selected_preset.get_remaining_starter_cards():
		_add_preview(_remaining_starter_preview_row, card_data)
	_queue_preview_position_refresh()


func _clear_preview_container(container: Control) -> void:
	for child in container.get_children():
		child.queue_free()


func _add_preview(parent: Control, card_data: CardData) -> void:
	var card := CARD_ENTITY_SCENE.instantiate() as CardEntity
	card.bind_instance(CardInstance.new(card_data))
	card.set_display_only(true)
	parent.add_child(card)


func _queue_preview_position_refresh() -> void:
	if _preview_position_refresh_queued:
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

	var root_previews := _root_preview_slot.get_children()
	for card in root_previews:
		if card is CardEntity:
			(card as CardEntity).position = _root_preview_slot.size * 0.5

	var remaining_previews := _remaining_starter_preview_row.get_children()
	var spacing := 112.0
	var total_width := maxf(0.0, (remaining_previews.size() - 1) * spacing)
	var start_x := (_remaining_starter_preview_row.size.x - total_width) * 0.5
	for index in remaining_previews.size():
		var card := remaining_previews[index] as CardEntity
		if card != null:
			card.position = Vector2(start_x + index * spacing, _remaining_starter_preview_row.size.y * 0.5)


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout(get_viewport().get_visible_rect().size)


func _apply_responsive_layout(viewport_size: Vector2) -> void:
	_main_area.vertical = viewport_size.x < 980.0


func _on_back_pressed() -> void:
	back_requested.emit()


func _on_start_exploration_pressed() -> void:
	if _exploration_requested or selected_preset == null or not selected_preset.is_unlocked:
		return

	_exploration_requested = true
	_start_exploration_button.disabled = true
	exploration_requested.emit(selected_preset)
