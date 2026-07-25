class_name CardEntity
extends Area2D

# ============================
# 信号（供 HandArea 使用）
# ============================
signal hovered(card: CardEntity)
signal unhovered(card: CardEntity)
signal clicked(card: CardEntity)

# ============================
# 状态
# ============================
enum State { NORMAL, HOVER, DRAGGING, ZOOMED }

var card_instance: CardInstance = null
var state: State = State.NORMAL
var _dragging: bool = false

# UI 元素
var _info_panel: Panel = null
var _zoom_overlay: CanvasLayer = null

# ============================
# 绑定
# ============================

func bind_instance(inst: CardInstance) -> void:
	card_instance = inst
	_update_visual()

# ============================
# 生命周期
# ============================

func _ready() -> void:
	input_pickable = true
	_build_info_panel()

	# 测试数据（如果没有绑定）
	if not card_instance:
		var data := CardData.new(0, "测试卡牌")
		var inst := CardInstance.new(data)
		bind_instance(inst)

# ============================
# 视觉更新
# ============================

func _update_visual() -> void:
	if not card_instance or not card_instance.card_data:
		return

	var label = $ColorRect/Label as Label
	if label:
		label.text = card_instance.card_data.card_name

# ============================
# 信息提示（悬浮）
# ============================

func _build_info_panel() -> void:
	_info_panel = Panel.new()
	_info_panel.name = "InfoPanel"
	_info_panel.visible = false
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.size = Vector2(140, 48)

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	bg_style.set_corner_radius_all(4)
	bg_style.set_border_width_all(1)
	bg_style.border_color = Color(0.3, 0.3, 0.5, 1.0)
	_info_panel.add_theme_stylebox_override("panel", bg_style)

	var info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.position = Vector2(8, 4)
	info_label.size = Vector2(124, 40)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_panel.add_child(info_label)

	add_child(_info_panel)

func _show_info(show_info: bool) -> void:
	if not _info_panel or not card_instance or not card_instance.card_data:
		return

	_info_panel.visible = show_info
	if show_info:
		var label = _info_panel.get_node("InfoLabel") as Label
		if label:
			var data = card_instance.card_data
			label.text = "ID: %d\n%s" % [data.card_id, data.card_name]

		# 定位到卡牌上方
		_info_panel.position = Vector2(
			-_info_panel.size.x / 2,
			-_info_panel.size.y - 90
		)

# ============================
# 悬停
# ============================

func _on_mouse_entered() -> void:
	if state == State.DRAGGING or state == State.ZOOMED:
		return

	state = State.HOVER
	_show_info(true)
	$ColorRect.modulate = Color(1.1, 1.1, 1.1)
	hovered.emit(self)

func _on_mouse_exited() -> void:
	if state == State.HOVER:
		state = State.NORMAL
		_show_info(false)
		$ColorRect.modulate = Color.WHITE
		unhovered.emit(self)

# ============================
# 鼠标输入
# ============================

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		match event.button_index:

			MOUSE_BUTTON_LEFT:
				print("left")
				if event.pressed:
					_start_drag()
				elif _dragging:
					_end_drag()
				else:
					clicked.emit(self)

			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					if _dragging:
						_rotate_card()
					elif state != State.ZOOMED and state != State.DRAGGING:
						_show_zoom()

# ============================
# 拖拽
# ============================

func _start_drag() -> void:
	_dragging = true
	state = State.DRAGGING
	$ColorRect.modulate = Color(1.2, 1.2, 1.0)
	_show_info(false)
	set_process(true)

	# reparent 到 DragLayer
	var drag_layer = get_tree().current_scene.get_node("DragLayer") as DragLayer
	if drag_layer:
		drag_layer.on_card_drag_start(self)

func _end_drag() -> void:
	_dragging = false
	state = State.NORMAL
	set_process(false)

	# 让 DragLayer 决定去哪里
	var drag_layer = get_tree().current_scene.get_node("DragLayer") as DragLayer
	if drag_layer:
		drag_layer.on_card_drag_end(self)

func _process(_delta: float) -> void:
	if _dragging:
		global_position = get_global_mouse_position()

# ============================
# 旋转
# ============================

func _rotate_card() -> void:
	if not card_instance:
		return

	card_instance.direction = (card_instance.direction + 1) % 4
	rotation_degrees = card_instance.direction * 90.0

# ============================
# 放大查看
# ============================

func _show_zoom() -> void:
	if state == State.ZOOMED:
		return

	state = State.ZOOMED

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
	bg.color = Color(0, 0, 0, 0.6)
	bg.size = get_viewport().get_visible_rect().size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_zoom_overlay.add_child(bg)

	# --- 放大卡片 ---
	var zoom_card = ColorRect.new()
	zoom_card.name = "ZoomCard"
	zoom_card.size = Vector2(240, 432)
	zoom_card.position = (bg.size - zoom_card.size) / 2
	zoom_card.color = Color(0.95, 0.95, 0.95)
	bg.add_child(zoom_card)

	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.15, 0.15, 0.2)
	card_style.set_corner_radius_all(8)
	card_style.set_border_width_all(2)
	card_style.border_color = Color(0.5, 0.6, 0.8, 1.0)
	zoom_card.add_theme_stylebox_override("panel", card_style)

	# 标题
	var title = Label.new()
	title.name = "Title"
	title.size = Vector2(200, 30)
	title.position = Vector2(20, 16)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_font_size_override("font_size", 20)
	if card_instance and card_instance.card_data:
		title.text = card_instance.card_data.card_name
	else:
		title.text = "卡牌"
	zoom_card.add_child(title)

	# 分隔线
	var h_line = ColorRect.new()
	h_line.color = Color(0.4, 0.4, 0.6, 0.6)
	h_line.size = Vector2(200, 1)
	h_line.position = Vector2(20, 52)
	zoom_card.add_child(h_line)

	# ID
	var id_label = Label.new()
	id_label.name = "IDLabel"
	id_label.size = Vector2(200, 20)
	id_label.position = Vector2(20, 60)
	id_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	id_label.add_theme_font_size_override("font_size", 12)
	if card_instance and card_instance.card_data:
		id_label.text = "卡牌 ID: %d" % card_instance.card_data.card_id
	else:
		id_label.text = "卡牌 ID: -"
	zoom_card.add_child(id_label)

	# 描述区域
	var desc_bg = ColorRect.new()
	desc_bg.color = Color(0.12, 0.12, 0.16)
	desc_bg.size = Vector2(200, 140)
	desc_bg.position = Vector2(20, 90)
	zoom_card.add_child(desc_bg)

	var desc_label = Label.new()
	desc_label.name = "Desc"
	desc_label.size = Vector2(188, 128)
	desc_label.position = Vector2(6, 6)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.text = "暂无描述"
	desc_bg.add_child(desc_label)

	# 关闭提示
	var hint = Label.new()
	hint.name = "Hint"
	hint.size = Vector2(200, 20)
	hint.position = Vector2(20, 240)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	hint.add_theme_font_size_override("font_size", 10)
	hint.text = "点击任意处关闭"
	zoom_card.add_child(hint)

	# --- 点击遮罩关闭 ---
	bg.gui_input.connect(_on_zoom_bg_input.bind(bg))

	# ESC 关闭
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
