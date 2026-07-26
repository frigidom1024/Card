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

var drag_layer

@onready var _card_view: ColorRect = $CardView

# UI 元素（悬浮提示）
var _info_panel: Panel = null

# UI 元素（放大）
var _zoom_overlay: CanvasLayer = null

# ============================
# 绑定
# ============================

func bind_instance(inst: CardInstance) -> void:
	card_instance = inst
	_card_view.set_value(inst)
	_card_view.refresh_display()


# ============================
# 生命周期
# ============================
func _ready() -> void:
	input_pickable = true
	card_instance=CardInstance.create_debug_card()
	_build_info_panel()


# ============================
# 信息提示（悬浮）
# ============================

func _build_info_panel() -> void:
	_info_panel = Panel.new()
	_info_panel.name = "InfoPanel"
	_info_panel.visible = false
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.size = Vector2(180, 120)

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	bg_style.set_corner_radius_all(6)
	bg_style.set_border_width_all(1)
	bg_style.border_color = Color(0.4, 0.4, 0.6, 1.0)
	_info_panel.add_theme_stylebox_override("panel", bg_style)

	var info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.position = Vector2(10, 8)
	info_label.size = Vector2(160, 104)
	info_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_panel.add_child(info_label)

	add_child(_info_panel)


func _show_info(show_info: bool) -> void:
	if not _info_panel or not card_instance or not card_instance.card_data:
		return

	_info_panel.visible = show_info
	if show_info:
		var label = _info_panel.get_node("InfoLabel") as Label
		if not label:
			return

		var data: CardData = card_instance.card_data
		var rarity_name = RARITY_NAMES.get(data.rarity, "COMMON")
		var rarity_color = RARITY_COLORS.get(data.rarity, RARITY_COLORS[CardData.Rarity.COMMON])

		# 第一行：名称 + 稀有度
		var text = "[color=#%s]%s[/color] [color=#%s](%s)[/color]\n" % [
			"ffffff", data.card_name,
			rarity_color.to_html(false), rarity_name,
		]

		# 第二行：类型 + ID
		text += "[color=#888899]ID:%d[/color]\n" % data.card_id

		# 第三行：属性
		var stats := ""
		if data.damage > 0:  stats += " ⚔%d" % data.damage
		if data.defense > 0: stats += " 🛡%d" % data.defense
		if data.heal > 0:    stats += " 💚%d" % data.heal
		if stats.length() > 0:
			text += "[color=#cccccc]%s[/color]\n" % stats

		# 第四行：标签
		var tag_names := ""
		for tag in data.tags:
			tag_names += " [color=#6699cc]%s[/color]" % TAG_NAMES.get(tag, "UNKN")
		if tag_names.length() > 0:
			text += tag_names + "\n"

		# 第五行：描述
		if data.description.length() > 0:
			text += "\n[color=#999999]%s[/color]" % data.description

		label.text = text

		# 根据内容调整面板高度
		var line_count = label.get_line_count()
		var new_height = max(60, line_count * 14 + 16)
		_info_panel.size.y = new_height
		label.size.y = new_height - 16

		# 定位到卡牌上方
		_info_panel.position = Vector2(
			-_info_panel.size.x / 2 + 5,
			-_info_panel.size.y - 85
		)


# ============================
# 悬停
# ============================

func _on_mouse_entered() -> void:
	if state == State.DRAGGING or state == State.ZOOMED:
		return

	state = State.HOVER
	_show_info(true)
	_card_view.modulate = Color(1.1, 1.1, 1.1)
	hovered.emit(self)


func _on_mouse_exited() -> void:
	if state == State.HOVER:
		state = State.NORMAL
		_show_info(false)
		_card_view.modulate = Color.WHITE
		unhovered.emit(self)


# ============================
# 鼠标输入
# ============================

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		match event.button_index:

			MOUSE_BUTTON_LEFT:
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
	_card_view.modulate = Color(1.2, 1.2, 1.0)
	_show_info(false)
	set_process(true)


	if drag_layer:
		drag_layer.on_card_drag_start(self)


func _end_drag() -> void:
	_dragging = false
	state = State.NORMAL
	set_process(false)

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
# 放大查看（完整数据展示）
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
	bg.color = Color(0, 0, 0, 0.65)
	bg.size = get_viewport().get_visible_rect().size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_zoom_overlay.add_child(bg)

	# --- 放大卡片 ---
	var data: CardData = card_instance.card_data if card_instance and card_instance.card_data else null
	var rarity_color = RARITY_COLORS.get(data.rarity if data else CardData.Rarity.COMMON, RARITY_COLORS[CardData.Rarity.COMMON])
	var rarity_name = RARITY_NAMES.get(data.rarity if data else CardData.Rarity.COMMON, "COMMON")

	var card_w = 260
	var card_h = 420
	var zoom_card = ColorRect.new()
	zoom_card.name = "ZoomCard"
	zoom_card.size = Vector2(card_w, card_h)
	zoom_card.position = (bg.size - zoom_card.size) / 2
	zoom_card.color = Color(0.12, 0.12, 0.16)
	bg.add_child(zoom_card)

	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.12, 0.16)
	card_style.set_corner_radius_all(10)
	card_style.set_border_width_all(2)
	card_style.border_color = rarity_color
	zoom_card.add_theme_stylebox_override("panel", card_style)

	# ---------- 顶部：稀有度标签 ----------
	var rarity_label = Label.new()
	rarity_label.size = Vector2(card_w - 40, 20)
	rarity_label.position = Vector2(20, 12)
	rarity_label.add_theme_color_override("font_color", rarity_color)
	rarity_label.add_theme_font_size_override("font_size", 11)
	rarity_label.text = "★ " + rarity_name
	zoom_card.add_child(rarity_label)

	# ---------- 标题 ----------
	var title = Label.new()
	title.size = Vector2(card_w - 40, 30)
	title.position = Vector2(20, 30)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_font_size_override("font_size", 18)
	title.text = data.card_name if data else "卡牌"
	zoom_card.add_child(title)

	# 分隔线1
	var h_line1 = ColorRect.new()
	h_line1.color = Color(0.35, 0.35, 0.5, 0.5)
	h_line1.size = Vector2(card_w - 40, 1)
	h_line1.position = Vector2(20, 66)
	zoom_card.add_child(h_line1)

	# ---------- ID + 类型 ----------
	var id_label = Label.new()
	id_label.size = Vector2(card_w - 40, 20)
	id_label.position = Vector2(20, 74)
	id_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.75))
	id_label.add_theme_font_size_override("font_size", 11)
	if data:
		id_label.text = "ID: %d" % data.card_id
	else:
		id_label.text = "ID: -"
	zoom_card.add_child(id_label)

	# ---------- 属性三栏 ----------
	var stat_y = 100
	var stat_w = (card_w - 60) / 3.0

	# ATK
	var atk_box = ColorRect.new()
	atk_box.color = Color(0.6, 0.15, 0.15, 0.3)
	atk_box.size = Vector2(stat_w, 44)
	atk_box.position = Vector2(20, stat_y)
	zoom_card.add_child(atk_box)

	var atk_icon = Label.new()
	atk_icon.size = Vector2(stat_w, 44)
	atk_icon.position = Vector2(20, stat_y)
	atk_icon.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	atk_icon.add_theme_font_size_override("font_size", 10)
	atk_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	atk_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	atk_icon.text = "⚔ ATK\n[color=#ffffff][b]%d[/b][/color]" % (data.damage if data else 0)
	zoom_card.add_child(atk_icon)

	# DEF
	var def_box = ColorRect.new()
	def_box.color = Color(0.15, 0.3, 0.55, 0.3)
	def_box.size = Vector2(stat_w, 44)
	def_box.position = Vector2(30 + stat_w, stat_y)
	zoom_card.add_child(def_box)

	var def_icon = Label.new()
	def_icon.size = Vector2(stat_w, 44)
	def_icon.position = Vector2(30 + stat_w, stat_y)
	def_icon.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	def_icon.add_theme_font_size_override("font_size", 10)
	def_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	def_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	def_icon.text = "🛡 DEF\n[color=#ffffff][b]%d[/b][/color]" % (data.defense if data else 0)
	zoom_card.add_child(def_icon)

	# HEAL
	var heal_box = ColorRect.new()
	heal_box.color = Color(0.15, 0.55, 0.3, 0.3)
	heal_box.size = Vector2(stat_w, 44)
	heal_box.position = Vector2(40 + stat_w * 2, stat_y)
	zoom_card.add_child(heal_box)

	var heal_icon = Label.new()
	heal_icon.size = Vector2(stat_w, 44)
	heal_icon.position = Vector2(40 + stat_w * 2, stat_y)
	heal_icon.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	heal_icon.add_theme_font_size_override("font_size", 10)
	heal_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heal_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heal_icon.text = "💚 HEAL\n[color=#ffffff][b]%d[/b][/color]" % (data.heal if data else 0)
	zoom_card.add_child(heal_icon)

	# 分隔线2
	var h_line2 = ColorRect.new()
	h_line2.color = Color(0.35, 0.35, 0.5, 0.5)
	h_line2.size = Vector2(card_w - 40, 1)
	h_line2.position = Vector2(20, 154)
	zoom_card.add_child(h_line2)

	# ---------- 标签 ----------
	var tag_y = 162
	var tag_label_title = Label.new()
	tag_label_title.size = Vector2(card_w - 40, 18)
	tag_label_title.position = Vector2(20, tag_y)
	tag_label_title.add_theme_color_override("font_color", Color(0.65, 0.65, 0.8))
	tag_label_title.add_theme_font_size_override("font_size", 10)
	tag_label_title.text = "TAGS"
	zoom_card.add_child(tag_label_title)

	var tag_line_y = tag_y + 20
	var tag_text := ""
	if data:
		for tag in data.tags:
			tag_text += "[color=#6699cc]%s[/color] " % TAG_NAMES.get(tag, "UNKN")

	var tag_value = Label.new()
	tag_value.size = Vector2(card_w - 40, 36)
	tag_value.position = Vector2(20, tag_line_y)
	tag_value.add_theme_font_size_override("font_size", 10)
	tag_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag_value.text = tag_text if tag_text.length() > 0 else "[color=#555555]--[/color]"
	zoom_card.add_child(tag_value)

	# 分隔线3
	var h_line3 = ColorRect.new()
	h_line3.color = Color(0.35, 0.35, 0.5, 0.5)
	h_line3.size = Vector2(card_w - 40, 1)
	h_line3.position = Vector2(20, 208)
	zoom_card.add_child(h_line3)

	# ---------- 描述 ----------
	var desc_label = Label.new()
	desc_label.size = Vector2(card_w - 40, 120)
	desc_label.position = Vector2(20, 216)
	desc_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.text = data.description if data and data.description.length() > 0 else "[color=#555555]暂无描述[/color]"
	zoom_card.add_child(desc_label)

	# ---------- 底部提示 ----------
	var hint_y = card_h - 30
	var hint = Label.new()
	hint.size = Vector2(card_w - 40, 20)
	hint.position = Vector2(20, hint_y)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.55))
	hint.add_theme_font_size_override("font_size", 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "点击任意处关闭 | 右键旋转"
	zoom_card.add_child(hint)

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
