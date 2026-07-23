# scripts/hand_area.gd
class_name HandArea
extends Node2D

# ===== 信号 =====
signal card_added(card: CardEntity)
signal card_removed(card: CardEntity)
signal card_selected(card: CardEntity)
signal card_hovered(card: CardEntity)
signal card_unhovered(card: CardEntity)

# ===== 导出参数 =====
@export_group("布局参数")
@export var card_width: float = 100.0
@export var card_spacing: float = 30.0
@export var arc_height: float = 60.0  # 拱形高度
@export var max_hand_size: int = 10

@export_group("交互参数")
@export var hover_scale: float = 1.3
@export var hover_offset: float = -50.0
@export var animation_duration: float = 0.15

@export_group("视觉效果")
@export var center_scale_boost: float = 0.1
@export var show_debug: bool = false

# ===== 内部状态 =====
var cards: Array[CardEntity] = []
var hovered_card: CardEntity = null
var selected_card: CardEntity = null

# ===== 生命周期 =====
func _ready() -> void:
	_draw_debug_info()

# ============================================================
# 核心方法
# ============================================================

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
	card.scale = Vector2.ONE
	card.z_index = 0
	
	# 3. 添加到列表
	cards.append(card)
	
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
	rearrange_cards(false)

func get_card_count() -> int:
	return cards.size()

func is_full() -> bool:
	return cards.size() >= max_hand_size

# ============================================================
# 布局算法（核心）
# ============================================================

func rearrange_cards(animate: bool = true) -> void:
	var count = cards.size()
	if count == 0:
		return
	
	# ---- 1. 计算总宽度 ----
	var total_width = (count - 1) * (card_width + card_spacing)
	var start_x = -total_width / 2
	var center_index = (count - 1) / 2.0
	
	# ---- 2. 逐张卡牌计算 ----
	for i in range(count):
		var card = cards[i]
		
		# ---- 位置计算 ----
		var x_pos = start_x + i * (card_width + card_spacing)
		
		# 拱形效果：正弦曲线
		var progress = float(i) / (count - 1) if count > 1 else 0.5
		var y_pos = -sin(progress * PI) * arc_height
		
		# ---- 缩放计算 ----
		var distance_from_center = abs(float(i) - center_index) / center_index if center_index > 0 else 0
		var base_scale = 1.0 + (1.0 - min(distance_from_center, 1.0)) * center_scale_boost
		
		# ---- Z轴层级 ----
		var z_index = int((1.0 - distance_from_center) * 10)
		
		# ---- 悬停状态修正 ----
		var final_pos = Vector2(x_pos, y_pos)
		var final_scale = Vector2(base_scale, base_scale)
		var final_z = z_index
		
		if card == hovered_card:
			# 悬停卡牌：上浮 + 放大
			final_pos.y += hover_offset
			final_scale = Vector2(hover_scale, hover_scale)
			final_z = 100
			
			# 推开相邻卡牌
			_apply_push_effect(i, count)
		
		# ---- 应用变换 ----
		if animate:
			_animate_card(card, final_pos, final_scale, final_z)
		else:
			card.position = final_pos
			card.scale = final_scale
			card.z_index = final_z

# ============================================================
# 交互效果
# ============================================================

func _apply_push_effect(hover_index: int, total_count: int) -> void:
	var push_distance = 40.0
	
	# 向左推
	if hover_index > 0:
		var left_card = cards[hover_index - 1]
		var push_pos = left_card.position + Vector2(-push_distance, -5)
		_animate_card(left_card, push_pos, left_card.scale, left_card.z_index)
	
	# 向右推
	if hover_index < total_count - 1:
		var right_card = cards[hover_index + 1]
		var push_pos = right_card.position + Vector2(push_distance, -5)
		_animate_card(right_card, push_pos, right_card.scale, right_card.z_index)

# ============================================================
# 动画工具
# ============================================================

var _tweens: Dictionary = {}

func _animate_card(card: CardEntity, target_pos: Vector2, target_scale: Vector2, target_z: int) -> void:
	# 取消旧动画
	if card in _tweens:
		_tweens[card].kill()
		_tweens.erase(card)
	
	# 创建新动画
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	
	tween.tween_property(card, "position", target_pos, animation_duration)
	tween.tween_property(card, "scale", target_scale, animation_duration)
	
	# Z轴直接设置（不缓动）
	card.z_index = target_z
	
	_tweens[card] = tween
	
	tween.finished.connect(func():
		if card in _tweens:
			_tweens.erase(card)
	)

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
		# 可以在这里添加取消选中的视觉效果
		pass
	
	if selected_card == card:
		selected_card = null
	else:
		selected_card = card
	
	card_selected.emit(card)

# ============================================================
# 调试
# ============================================================

func _draw_debug_info() -> void:
	# 在场景中绘制一个边框，显示手牌区范围
	var rect = ColorRect.new()
	rect.color = Color(0, 1, 0, 0.1)
	rect.size = Vector2(800, 200)
	rect.position = -rect.size / 2
	add_child(rect)
	
	var label = Label.new()
	label.text = "手牌区"
	label.position = Vector2(-20, -100)
	add_child(label)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()
	if get_child_count() == 0:
		warnings.append("HandArea 没有子节点。请通过代码添加卡牌。")
	return warnings
