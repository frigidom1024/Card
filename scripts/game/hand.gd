# scripts/hand_area.gd
class_name HandArea
extends Node2D

# ===== 信号 =====
signal card_added(card: CardEntity)
signal card_removed(card: CardEntity)
signal hand_count_changed(current_count: int, max_count: int)
signal card_selected(card: CardEntity)
signal card_hovered(card: CardEntity)
signal card_unhovered(card: CardEntity)

# ===== 导出参数 =====
@export_group("布局参数")
@export var card_width: float = LayoutConfig.CARD_W
@export var card_spacing: float = LayoutConfig.HAND_SPACING
@export var max_hand_size: int = 10

@export_group("交互参数")
@export var hover_scale: float = 1.2
@export var hover_offset: float = -40.0
@export var animation_duration: float = 0.15

# ===== 内部状态 =====
var cards: Array[CardEntity] = []
var hovered_card: CardEntity = null
var selected_card: CardEntity = null

# ============================================================
# 核心方法
# ============================================================

func _emit_hand_count_changed() -> void:
	hand_count_changed.emit(cards.size(), max_hand_size)


func add_card(card: CardEntity, animate: bool = true) -> bool:
	# 检查是否已满
	if cards.size() >= max_hand_size:
		push_warning("手牌已满，无法添加卡牌")
		return false

	# 检查是否已存在
	if card in cards:
		push_warning("卡牌已在手牌中")
		return false

	# 1. 重新父节点到手牌区
	if card.get_parent():
		card.reparent(self)
	else:
		add_child(card)

	# 2. 重置卡牌状态
	card.set_on_board(false)
	card.scale = Vector2.ONE
	card.z_index = RenderPriority.CARD_BASE

	# 3. 添加到列表
	cards.append(card)
	_emit_hand_count_changed()

	# 4. 连接信号
	_connect_card_signals(card)

	# 5. 重新排列
	rearrange_cards(animate)

	# 6. 发射信号
	card_added.emit(card)

	return true

func remove_card(card: CardEntity, animate: bool = true) -> bool:
	if card not in cards:
		return false

	# 1. 从列表中移除
	cards.erase(card)
	_emit_hand_count_changed()

	# 2. 断开信号
	_disconnect_card_signals(card)

	# 3. 重新排列
	rearrange_cards(animate)

	# 4. 发射信号
	card_removed.emit(card)

	return true

func clear_hand() -> void:
	for card in cards:
		_disconnect_card_signals(card)

	cards.clear()
	_emit_hand_count_changed()
	rearrange_cards(false)

func get_card_count() -> int:
	return cards.size()

func is_full() -> bool:
	return cards.size() >= max_hand_size

# ============================================================
# 布局算法（简化版：横向排列）
# ============================================================

func rearrange_cards(animate: bool = true) -> void:
	var count = cards.size()
	if count == 0:
		return

	# 计算起始 X 位置（居中）
	var total_width = (count - 1) * (card_width + card_spacing)
	var start_x = -total_width / 2

	for i in range(count):
		var card = cards[i]

		# 基础位置：横向排列
		var x_pos = start_x + i * (card_width + card_spacing)
		var final_pos = Vector2(x_pos, 0)
		var final_scale = Vector2.ONE
		var final_z = RenderPriority.CARD_BASE + i

		# 悬停效果：上浮 + 放大
		if card == hovered_card:
			final_pos.y += hover_offset
			final_scale = Vector2(hover_scale, hover_scale)
			final_z = RenderPriority.CARD_HAND_HOVER

		# 应用变换
		if animate:
			_animate_card(card, final_pos, final_scale, final_z)
		else:
			card.position = final_pos
			card.scale = final_scale
			card.z_index = final_z


# ============================================================
# 动画工具
# ============================================================

var _tweens: Dictionary = {}

func _animate_card(card: CardEntity, target_pos: Vector2, target_scale: Vector2, target_z: int) -> void:
	var card_id := card.get_instance_id()
	# 取消旧动画
	if card_id in _tweens:
		_tweens[card_id].kill()
		_tweens.erase(card_id)

	# 创建新动画
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(card, "position", target_pos, animation_duration)
	tween.tween_property(card, "scale", target_scale, animation_duration)

	# Z轴直接设置（不缓动）
	card.z_index = target_z

	_tweens[card_id] = tween
	tween.finished.connect(func(): _tweens.erase(card_id))
# ============================================================
# 信号管理
# ============================================================

func _connect_card_signals(card: CardEntity) -> void:
	if not card.hovered.is_connected(_on_card_hovered):
		card.hovered.connect(_on_card_hovered)
		card.unhovered.connect(_on_card_unhovered)
		card.clicked.connect(_on_card_clicked)

func _disconnect_card_signals(card: CardEntity) -> void:
	if card.hovered.is_connected(_on_card_hovered):
		card.hovered.disconnect(_on_card_hovered)
		card.unhovered.disconnect(_on_card_unhovered)
		card.clicked.disconnect(_on_card_clicked)

# ============================================================
# 信号处理
# ============================================================

func _on_card_hovered(card: CardEntity) -> void:
	hovered_card = card
	card_hovered.emit(card)
	rearrange_cards(true)

func _on_card_unhovered(card: CardEntity) -> void:
	if hovered_card == card:
		hovered_card = null
		card_unhovered.emit(card)
		rearrange_cards(true)

func _on_card_clicked(card: CardEntity) -> void:
	# 取消之前的选择
	if selected_card and selected_card != card:
		pass

	if selected_card == card:
		selected_card = null
	else:
		selected_card = card

	card_selected.emit(card)
