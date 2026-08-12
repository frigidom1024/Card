class_name CardEntity
extends Area2D

## CardEntity is the stable gameplay-facing facade for a card.
##
## The node remains an Area2D because board/hand systems depend on its collision
## and public signals. UI responsibilities are composed below it:
## - CardInteractionController: hover, input, drag and rotation
## - CardDisplayController: CardView layout and visual state
## - CardInfoController: hover details and zoom overlay
## - CardTagController: combat stat badges

signal hovered(card: CardEntity)
signal unhovered(card: CardEntity)
signal clicked(card: CardEntity)

enum State { NORMAL, HOVER, DRAGGING, ZOOMED }

var card_instance: CardInstance = null
var state: State = State.NORMAL
var drag_layer
var _dragging: bool = false
var _consume_next_left_release := false
var _display_only := false
var _display_info_enabled := false
var _display_zoom_enabled := false
var _market_offer := false
var _on_board := false
var _card_info_overlay: CardInfoOverlay = null
var _zoom_overlay: CanvasLayer = null

@export var zoom_view_scene: PackedScene

@onready var _card_view: Control = $CardView
@onready var _combat_tag_anchor: Control = $CombatTagAnchor
@onready var _tag_container: HBoxContainer = $CombatTagAnchor/TagContainer
@onready var _interaction_controller: Node = $CardInteractionController
@onready var _display_controller: Node = $CardDisplayController
@onready var _info_controller: Node = $CardInfoController
@onready var _tag_controller: Node = $CardTagController


func _ready() -> void:
	set_notify_transform(true)
	if card_instance == null:
		card_instance = CardInstance.create_debug_card()
	_configure_controllers()
	input_pickable = _should_be_input_pickable()
	_apply_layout()
	_display_controller.bind_instance(card_instance)
	_display_controller.set_on_board(_on_board)
	_tag_controller.refresh(card_instance)


func _configure_controllers() -> void:
	_interaction_controller.configure(self, _card_view)
	_display_controller.configure(_card_view)
	_info_controller.configure(self, zoom_view_scene)
	_tag_controller.configure(self, _combat_tag_anchor, _tag_container)
	_configure_card_view_pointer_input()


func bind_instance(inst: CardInstance) -> void:
	card_instance = inst
	if not is_inside_tree():
		return
	_display_controller.bind_instance(inst)
	_tag_controller.refresh(inst)


## 让卡牌作为静态预览展示，不参与游戏内交互。
func set_display_only(value: bool, show_info_on_hover := false, allow_zoom_on_right_click := false) -> void:
	if value:
		if state == State.ZOOMED:
			_hide_zoom()
		_cancel_drag_without_signal()
		_set_card_state(State.NORMAL)
		_set_visual_highlight(false)
		set_process_input(false)

	_display_only = value
	_display_info_enabled = value and show_info_on_hover
	_display_zoom_enabled = value and allow_zoom_on_right_click
	input_pickable = _should_be_input_pickable()
	_configure_card_view_pointer_input()
	if value:
		_show_info(false)


func is_display_only() -> bool:
	return _display_only


func set_market_offer_mode(value: bool) -> void:
	if value and state == State.ZOOMED:
		_hide_zoom()
	_cancel_drag_without_signal()
	_set_card_state(State.NORMAL)
	_market_offer = value
	_display_only = false
	_display_info_enabled = value
	_display_zoom_enabled = value
	input_pickable = true
	_configure_card_view_pointer_input()
	_show_info(false)


func is_market_offer() -> bool:
	return _market_offer


func set_on_board(value: bool) -> void:
	_on_board = value
	if is_node_ready():
		_display_controller.set_on_board(value)


# ============================
# Compatibility facade methods
# ============================

func _configure_card_view_pointer_input() -> void:
	if not is_node_ready():
		return
	_interaction_controller.configure_pointer_input(
		_display_only,
		_market_offer,
		_display_info_enabled,
		_display_zoom_enabled
	)


func _apply_layout() -> void:
	if not is_node_ready():
		return
	var shape := RectangleShape2D.new()
	shape.size = Vector2(LayoutConfig.CELL_SIZE, LayoutConfig.CELL_SIZE * 2.0)
	$CollisionShape2D.shape = shape
	_display_controller.apply_layout(LayoutConfig.CELL_SIZE)
	call_deferred("_position_combat_tags")


func refresh_combat_tags() -> void:
	if is_node_ready():
		_tag_controller.refresh(card_instance)


func _position_combat_tags() -> void:
	if is_node_ready():
		_tag_controller.position()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_position_combat_tags()


func _show_info(show_info: bool) -> void:
	if is_node_ready():
		_info_controller.show_info(show_info, _display_only, _display_info_enabled)


func get_card_view_screen_rect() -> Rect2:
	if not is_node_ready():
		return Rect2()
	return _display_controller.get_screen_rect()


func _on_mouse_entered() -> void:
	_interaction_controller.on_mouse_entered()


func _on_mouse_exited() -> void:
	_interaction_controller.on_mouse_exited()


func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	_interaction_controller.on_input_event(viewport, event, shape_idx)


func _start_drag() -> void:
	_interaction_controller.start_drag()
	_dragging = _interaction_controller.is_dragging()


func _end_drag() -> void:
	_interaction_controller.end_drag()
	_dragging = _interaction_controller.is_dragging()


func cancel_drag_for_interaction_lock() -> void:
	_consume_next_left_release = true
	_interaction_controller.cancel_drag_for_interaction_lock()
	_dragging = false


func cancel_drag() -> void:
	_interaction_controller.cancel_drag()
	_dragging = false


func rotate_while_dragging() -> bool:
	return _interaction_controller.rotate_while_dragging()


# ============================
# Info/zoom compatibility facade
# ============================

func _show_zoom() -> void:
	_info_controller.show_zoom(_display_only, _display_zoom_enabled)


func _on_zoom_bg_input(event: InputEvent, background: ColorRect) -> void:
	_info_controller._on_zoom_background_input(event, background)


func _hide_zoom() -> void:
	_info_controller.hide_zoom()


func _input(event: InputEvent) -> void:
	_info_controller.handle_unhandled_input(event)


func _set_card_state(next_state: State) -> void:
	state = next_state


func _set_dragging_state(value: bool) -> void:
	_dragging = value


func _set_visual_highlight(active: bool) -> void:
	if is_node_ready():
		_display_controller.set_interaction_highlight(active)


func _set_drag_highlight(active: bool) -> void:
	if is_node_ready():
		_display_controller.set_drag_highlight(active)


func _cancel_drag_without_signal() -> void:
	if is_node_ready():
		_interaction_controller.cancel_drag()
	_dragging = false


func _should_be_input_pickable() -> bool:
	return not _display_only or _display_info_enabled or _display_zoom_enabled or _market_offer


func _exit_tree() -> void:
	if is_node_ready():
		_info_controller.cleanup()
