class_name CardEntity
extends Area2D

# ============================
# 信号（供 HandArea 使用）
# ============================
signal hovered(card: CardEntity)
signal unhovered(card: CardEntity)
signal clicked(card: CardEntity)

# ============================
# 稀有度颜色
# ============================
const RARITY_COLORS := {
	CardData.Rarity.COMMON:    Color(0.7, 0.7, 0.75),
	CardData.Rarity.RARE:      Color(0.3, 0.5, 0.95),
	CardData.Rarity.EPIC:      Color(0.6, 0.3, 0.9),
	CardData.Rarity.LEGENDARY: Color(0.95, 0.75, 0.2),
}

const RARITY_NAMES := {
	CardData.Rarity.COMMON:    "COMMON",
	CardData.Rarity.RARE:      "RARE",
	CardData.Rarity.EPIC:      "EPIC",
	CardData.Rarity.LEGENDARY: "LEGENDARY",
}

const TAG_NAMES := {
	CardData.CardTag.WEAPON:    "WEAPON",
	CardData.CardTag.DEFENSE:   "DEFENSE",
	CardData.CardTag.HEAL:      "HEAL",
	CardData.CardTag.RESOURCE:  "RESOURCE",
	CardData.CardTag.LOCATION:  "LOCATION",
	CardData.CardTag.CREATURE:  "CREATURE",
	CardData.CardTag.ITEM:      "ITEM",
	CardData.CardTag.EVENT:     "EVENT",
	CardData.CardTag.HOLY:      "HOLY",
	CardData.CardTag.DARK:      "DARK",
	CardData.CardTag.NATURE:    "NATURE",
}

const STAT_TAG_SCENES := {
	"damage": preload("res://scenes/card_view/stat_tags/card_stat_tag_damage.tscn"),
	"guard": preload("res://scenes/card_view/stat_tags/card_stat_tag_guard.tscn"),
	"heal": preload("res://scenes/card_view/stat_tags/card_stat_tag_heal.tscn"),
}
const CARD_INFO_OVERLAY_SCENE := preload("res://scenes/card_view/card_info_overlay.tscn")
# ============================
# 状态
# ============================
enum State { NORMAL, HOVER, DRAGGING, ZOOMED }

var card_instance: CardInstance = null
var state: State = State.NORMAL
var _dragging: bool = false
var _consume_next_left_release := false
var _display_only := false
var _display_info_enabled := false
var _display_zoom_enabled := false
var _market_offer := false
var _on_board := false

var drag_layer
var _card_info_overlay: CardInfoOverlay = null

@onready var _card_view: ColorRect = $CardView
@onready var _combat_tag_anchor: Control = $CombatTagAnchor
@onready var _tag_container: HBoxContainer = $CombatTagAnchor/TagContainer

# UI 元素（放大）
var _zoom_overlay: CanvasLayer = null

# ============================
# 绑定
# ============================

func bind_instance(inst: CardInstance) -> void:
	card_instance = inst
	if _card_view and is_inside_tree():
		_card_view.set_value(inst)
		_card_view.refresh_display()
		_refresh_combat_tags()


## 让卡牌作为静态预览展示，不参与任何游戏内交互。
func set_display_only(value: bool, show_info_on_hover := false, allow_zoom_on_right_click := false) -> void:
	if value:
		if state == State.ZOOMED:
			_hide_zoom()
		_dragging = false
		state = State.NORMAL
		set_process(false)
		set_process_input(false)
		if _card_view:
			_card_view.modulate = Color.WHITE
		_show_info(false)

	_display_only = value
	_display_info_enabled = _display_only and show_info_on_hover
	_display_zoom_enabled = _display_only and allow_zoom_on_right_click
	input_pickable = not _display_only or _display_info_enabled or _display_zoom_enabled or _market_offer
	_configure_card_view_pointer_input()


func is_display_only() -> bool:
	return _display_only



func set_market_offer_mode(value: bool) -> void:
	if value and state == State.ZOOMED:
		_hide_zoom()
	_dragging = false
	state = State.NORMAL
	set_process(false)
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
	if _card_view:
		_card_view.set_head_indicator_visible(value)


# ============================
# 生命周期
# ============================
func _ready() -> void:
	input_pickable = not _display_only or _display_info_enabled or _display_zoom_enabled or _market_offer
	set_notify_transform(true)
	_combat_tag_anchor.z_index = RenderPriority.CARD_COMBAT_TAG
	if not card_instance:
		card_instance = CardInstance.create_debug_card()
	_card_view.set_value(card_instance)
	_card_view.set_head_indicator_visible(_on_board)
	_configure_card_view_pointer_input()
	_apply_layout()
	_refresh_combat_tags()


func _configure_card_view_pointer_input() -> void:
	if _card_view == null:
		return

	var accepts_preview_pointer_input := (_display_only or _market_offer) and (
		_display_info_enabled or _display_zoom_enabled
	)
	_card_view.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if accepts_preview_pointer_input
		else Control.MOUSE_FILTER_IGNORE
	)
	if not _card_view.mouse_entered.is_connected(_on_card_view_mouse_entered):
		_card_view.mouse_entered.connect(_on_card_view_mouse_entered)
	if not _card_view.mouse_exited.is_connected(_on_card_view_mouse_exited):
		_card_view.mouse_exited.connect(_on_card_view_mouse_exited)
	if not _card_view.gui_input.is_connected(_on_card_view_gui_input):
		_card_view.gui_input.connect(_on_card_view_gui_input)


func _on_card_view_mouse_entered() -> void:
	_on_mouse_entered()


func _on_card_view_mouse_exited() -> void:
	_on_mouse_exited()


func _on_card_view_gui_input(event: InputEvent) -> void:
	_on_input_event(get_viewport(), event, 0)


## 卡牌尺寸由 LayoutConfig.CELL_SIZE 派生（碰撞盒 1×2 格，卡面居中）
func _apply_layout() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(LayoutConfig.CELL_SIZE, LayoutConfig.CELL_SIZE * 2)
	$CollisionShape2D.shape = shape

	var rect := LayoutConfig.card_view_rect(LayoutConfig.CELL_SIZE)
	_card_view.offset_left = rect.position.x
	_card_view.offset_top = rect.position.y
	_card_view.offset_right = rect.position.x + rect.size.x
	_card_view.offset_bottom = rect.position.y + rect.size.y
	call_deferred("_position_combat_tags")


func _refresh_combat_tags() -> void:
	if _tag_container == null:
		return

	for child in _tag_container.get_children():
		child.queue_free()

	if card_instance == null or card_instance.card_data == null:
		return

	var data := card_instance.card_data
	var stat_entries := [
		{"scene": STAT_TAG_SCENES["damage"], "value": data.damage},
		{"scene": STAT_TAG_SCENES["guard"], "value": data.defense},
		{"scene": STAT_TAG_SCENES["heal"], "value": data.heal},
	]
	for entry in stat_entries:
		var value: int = entry["value"]
		if value <= 0:
			continue
		var tag := (entry["scene"] as PackedScene).instantiate() as Control
		(tag.get_node("ValueLabel") as Label).text = str(value)
		_tag_container.add_child(tag)

	call_deferred("_position_combat_tags")


func _position_combat_tags() -> void:
	if _combat_tag_anchor == null or _tag_container == null:
		return

	var tag_size := _tag_container.get_combined_minimum_size()
	_combat_tag_anchor.size = tag_size
	_tag_container.size = tag_size
	var card_rect := LayoutConfig.card_view_rect(LayoutConfig.CELL_SIZE)
	var global_bottom_center: Vector2 = _global_bottom_edge_center(card_rect) + Vector2(0.0, 2.0)
	_combat_tag_anchor.rotation = 0.0
	_combat_tag_anchor.global_position = global_bottom_center - tag_size * 0.5


func _global_bottom_edge_center(card_rect: Rect2) -> Vector2:
	var global_corners: Array[Vector2] = [
		to_global(card_rect.position),
		to_global(card_rect.position + Vector2(card_rect.size.x, 0.0)),
		to_global(card_rect.position + card_rect.size),
		to_global(card_rect.position + Vector2(0.0, card_rect.size.y)),
	]
	var global_bottom_center: Vector2 = (global_corners[0] + global_corners[1]) * 0.5
	for corner_index in range(global_corners.size()):
		var next_corner_index := (corner_index + 1) % global_corners.size()
		var candidate_center: Vector2 = (global_corners[corner_index] + global_corners[next_corner_index]) * 0.5
		if candidate_center.y > global_bottom_center.y:
			global_bottom_center = candidate_center
	return global_bottom_center


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_position_combat_tags()
# ============================
# 信息提示（悬浮）
# ============================

func _show_info(show_info: bool) -> void:
	if show_info:
		if (_display_only and not _display_info_enabled) or card_instance == null or card_instance.card_data == null:
			return
		var overlay := _get_card_info_overlay()
		if overlay != null:
			overlay.show_for_card(self)
	elif _card_info_overlay != null and is_instance_valid(_card_info_overlay):
		_card_info_overlay.hide_for_card(self)


func _get_card_info_overlay() -> CardInfoOverlay:
	if _card_info_overlay != null and is_instance_valid(_card_info_overlay):
		return _card_info_overlay

	_card_info_overlay = CARD_INFO_OVERLAY_SCENE.instantiate() as CardInfoOverlay
	if _card_info_overlay == null:
		push_error("CardEntity could not instantiate CardInfoOverlay")
		return null
	_card_info_overlay.name = "CardInfoOverlay"
	add_child(_card_info_overlay)
	return _card_info_overlay


func get_card_view_screen_rect() -> Rect2:
	var transform := _card_view.get_global_transform_with_canvas()
	var screen_rect := Rect2(transform * Vector2.ZERO, Vector2.ZERO)
	for corner in [
		Vector2.ZERO,
		Vector2(_card_view.size.x, 0.0),
		Vector2(0.0, _card_view.size.y),
		_card_view.size,
	]:
		screen_rect = screen_rect.expand(transform * corner)
	return screen_rect


# ============================
# 悬停
# ============================

func _on_mouse_entered() -> void:
	if drag_layer and drag_layer.is_drag_active():
		return

	if _display_only:
		if _display_info_enabled:
			_show_info(true)
		return

	if state == State.DRAGGING or state == State.ZOOMED:
		return

	state = State.HOVER
	_show_info(true)
	_card_view.modulate = Color(1.1, 1.1, 1.1)
	hovered.emit(self)


func _on_mouse_exited() -> void:
	if _display_only:
		if _display_info_enabled:
			_show_info(false)
		return

	if state == State.HOVER:
		state = State.NORMAL
		_show_info(false)
		_card_view.modulate = Color.WHITE
		unhovered.emit(self)


# ============================
# 鼠标输入
# ============================

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _market_offer:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_start_drag()
				elif _dragging:
					_end_drag()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_show_info(false)
				_show_zoom()
		return
	if _display_only:
		if _display_zoom_enabled and event is InputEventMouseButton \
				and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_show_info(false)
			_show_zoom()
		return

	if event is InputEventMouseButton:
		match event.button_index:

			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_start_drag()
				elif drag_layer and drag_layer.is_interaction_locked():
					_consume_next_left_release = false
					return
				elif _consume_next_left_release:
					_consume_next_left_release = false
					return
				elif _dragging:
					_end_drag()
				else:
					clicked.emit(self)

			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_show_info(false)  # 先关闭信息窗口
					if _dragging:
						rotate_while_dragging()
					elif state != State.ZOOMED and state != State.DRAGGING:
						# 拖拽路过时误触其他卡牌的右键 → 不放大
						if drag_layer and drag_layer._dragged_card != null:
							return
						_show_zoom()


# ============================
# 拖拽
# ============================

func _start_drag() -> void:
	if _display_only and not _market_offer:
		return

	if drag_layer and drag_layer.is_interaction_locked():
		return
	if drag_layer and not drag_layer.can_start_drag(self):
		return

	_dragging = true
	state = State.DRAGGING
	_card_view.modulate = Color(1.2, 1.2, 1.0)
	_show_info(false)
	set_process(true)

	if drag_layer:
		drag_layer.on_card_drag_start(self)


func _end_drag() -> void:
	if drag_layer and drag_layer.is_interaction_locked():
		return

	_dragging = false
	state = State.NORMAL
	set_process(false)

	if drag_layer:
		drag_layer.on_card_drag_end(self)


func cancel_drag_for_interaction_lock() -> void:
	_consume_next_left_release = true
	cancel_drag()


func cancel_drag() -> void:
	_dragging = false
	state = State.NORMAL
	set_process(false)
	_card_view.modulate = Color.WHITE


func _process(_delta: float) -> void:
	if _dragging:
		global_position = get_global_mouse_position()
		_position_combat_tags()


# ============================
# 旋转
# ============================

func rotate_while_dragging() -> bool:
	if _market_offer or not _dragging:
		return false
	_show_info(false)
	_rotate_card()
	return true


func _rotate_card() -> void:
	if _display_only or _market_offer:
		return

	if not card_instance:
		return

	card_instance.direction = (card_instance.direction + 1) % 4
	rotation_degrees = card_instance.direction * 90.0
	_position_combat_tags()


# ============================
# 放大查看（完整数据展示）—— 使用预制场景
# ============================

@export var zoom_view_scene:PackedScene

func _show_zoom() -> void:
	if _display_only and not _display_zoom_enabled:
		return

	if state == State.ZOOMED:
		return

	state = State.ZOOMED
	_show_info(false)

	# --- 创建覆盖层 ---
	_zoom_overlay = CanvasLayer.new()
	_zoom_overlay.layer = RenderPriority.CARD_ZOOM_OVERLAY
	_zoom_overlay.name = "CardZoomOverlay"

	var root = get_tree().current_scene
	if not root:
		return
	root.add_child(_zoom_overlay)

	# 背景遮罩
	var bg = ColorRect.new()
	bg.name = "ZoomBg"
	bg.color = Color("070b12b8")
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_zoom_overlay.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# --- 使用预制场景 ---
	var zoom_view = zoom_view_scene.instantiate()
	zoom_view.name = "ZoomView"
	zoom_view.set_data(card_instance)
	bg.add_child(zoom_view)
	zoom_view.set_anchors_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	_center_zoom_view(zoom_view, bg)
	zoom_view.resized.connect(_center_zoom_view.bind(zoom_view, bg))
	bg.resized.connect(_center_zoom_view.bind(zoom_view, bg))
	# refresh_display 会在 _ready() 中自动调用

	# --- 点击遮罩关闭 ---
	bg.gui_input.connect(_on_zoom_bg_input.bind(bg))
	set_process_input(true)


func _center_zoom_view(zoom_view: Control, bg: Control) -> void:
	zoom_view.position = (bg.size - zoom_view.size) * 0.5


func _on_zoom_bg_input(event: InputEvent, bg: ColorRect) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return

	var zoom_view := bg.get_node_or_null("ZoomView") as Control
	if zoom_view and zoom_view.get_global_rect().has_point(event.position):
		return

	_hide_zoom()


func _input(event: InputEvent) -> void:
	if state == State.ZOOMED and event.is_action_pressed("ui_cancel"):
		_hide_zoom()


func _hide_zoom() -> void:
	state = State.NORMAL
	set_process_input(false)
	if _zoom_overlay:
		_zoom_overlay.queue_free()
		_zoom_overlay = null


# ============================
# 清理
# ============================

func _exit_tree() -> void:
	_show_info(false)
	if _zoom_overlay:
		_zoom_overlay.queue_free()
		_zoom_overlay = null
