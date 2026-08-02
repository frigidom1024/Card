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

# ============================
# 状态
# ============================
enum State { NORMAL, HOVER, DRAGGING, ZOOMED }

var card_instance: CardInstance = null
var state: State = State.NORMAL
var _dragging: bool = false
var _consume_next_left_release := false
var _display_only := false

var drag_layer

@onready var _card_view: ColorRect = $CardView
@onready var _card_info: PanelContainer = $CardInfo

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


## 让卡牌作为静态预览展示，不参与任何游戏内交互。
func set_display_only(value: bool) -> void:
	if value:
		if state == State.ZOOMED:
			_hide_zoom()
		_dragging = false
		state = State.NORMAL
		set_process(false)
		set_process_input(false)
		if _card_view:
			_card_view.modulate = Color.WHITE
		if _card_info:
			_card_info.hide_floating()

	_display_only = value
	input_pickable = not _display_only


func is_display_only() -> bool:
	return _display_only


# ============================
# 生命周期
# ============================
func _ready() -> void:
	input_pickable = not _display_only
	if not card_instance:
		card_instance = CardInstance.create_debug_card()
	_card_view.set_value(card_instance)
	_apply_layout()


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


# ============================
# 信息提示（悬浮）
# ============================

func _show_info(show_info: bool) -> void:
	if _display_only:
		return

	if not _card_info or not card_instance or not card_instance.card_data:
		if not _card_info:
			print("missing _card_info")
		if not card_instance:
			print("missing card_instance")
		if not card_instance.card_data:
			print("card_instance.card_data")
		return

	if show_info:
		# 定位到卡牌右侧，顶部对齐（局部坐标）
		var offset = Vector2(
			_card_view.offset_left + _card_view.size.x + 8,
			_card_view.offset_top - 4
		)
		_card_info.show_as_floating(card_instance, offset)
	else:
		_card_info.hide_floating()


# ============================
# 悬停
# ============================

func _on_mouse_entered() -> void:
	if _display_only:
		return

	if state == State.DRAGGING or state == State.ZOOMED:
		return

	state = State.HOVER
	_show_info(true)
	_card_view.modulate = Color(1.1, 1.1, 1.1)
	hovered.emit(self)


func _on_mouse_exited() -> void:
	if _display_only:
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
	if _display_only:
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
						_rotate_card()
					elif state != State.ZOOMED and state != State.DRAGGING:
						# 拖拽路过时误触其他卡牌的右键 → 不放大
						if drag_layer and drag_layer._dragged_card != null:
							return
						_show_zoom()


# ============================
# 拖拽
# ============================

func _start_drag() -> void:
	if _display_only:
		return

	if drag_layer and drag_layer.is_interaction_locked():
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


# ============================
# 旋转
# ============================

func _rotate_card() -> void:
	if _display_only:
		return

	if not card_instance:
		return

	card_instance.direction = (card_instance.direction + 1) % 4
	rotation_degrees = card_instance.direction * 90.0


# ============================
# 放大查看（完整数据展示）—— 使用预制场景
# ============================

@export var zoom_view_scene:PackedScene

func _show_zoom() -> void:
	if _display_only:
		return

	if state == State.ZOOMED:
		return

	state = State.ZOOMED
	_show_info(false)

	# --- 创建覆盖层 ---
	_zoom_overlay = CanvasLayer.new()
	_zoom_overlay.layer = 128
	_zoom_overlay.name = "CardZoomOverlay"

	var root = get_tree().current_scene
	if not root:
		return
	root.add_child(_zoom_overlay)

	# 背景遮罩
	var bg = ColorRect.new()
	bg.name = "ZoomBg"
	bg.color = Color(0, 0, 0, 0.65)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_zoom_overlay.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# --- 使用预制场景 ---
	var zoom_view = zoom_view_scene.instantiate()
	zoom_view.name = "ZoomView"
	zoom_view.set_data(card_instance)
	bg.add_child(zoom_view)
	# 居中显示
	zoom_view.set_anchors_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	# refresh_display 会在 _ready() 中自动调用

	# --- 点击遮罩关闭 ---
	bg.gui_input.connect(_on_zoom_bg_input.bind(bg))
	set_process_input(true)


func _on_zoom_bg_input(event: InputEvent, _bg: ColorRect) -> void:
	if event is InputEventMouseButton and event.pressed:
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
	if _zoom_overlay:
		_zoom_overlay.queue_free()
		_zoom_overlay = null
