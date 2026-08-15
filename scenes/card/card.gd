## 卡牌实体组件
##
## 负责管理一张卡牌在游戏世界中的表现与拖拽交互。
## 包括：
## - CardInstance 的精确绑定
## - 点数、护甲与卡面图片的显示
## - 鼠标悬停、拖拽与视觉反馈
## - 拖拽过程中与 DraggerLayer 的通信
##
## 不负责：
## - 卡牌数据的持久化
## - 卡牌所在区域的管理
## - 卡牌是否合法放置的规则判断
## - CardInstance 状态变更的业务决策
##
## 使用方式：
## 通过 bind_card_inst() 注入一个 CardInstance，必要时在实例状态变化后调用
## refresh_display()；通过 bind_drag_layer() 接入当前页面的拖拽层。
##
## 依赖：
## CardInstance：提供卡牌的唯一运行时状态。
## DraggerLayer：接收卡牌拖拽生命周期通知。

extends Button
class_name Card
@onready var card_texture: Control = $CardTexture
@onready var shadow:Control = $Shadow
@onready var artwork: TextureRect = $CardTexture/SubViewport/Artwork
@onready var attack_label: Label = $CardTexture/SubViewport/AttackLabel/Label
@onready var defense_label: Label = $CardTexture/SubViewport/DefenseLabel/Label
@export var angle_x_max: float = 8.0
@export var angle_y_max: float = 8.0
@export var max_offset_shadow:float=6.0


var tween_rot: Tween
var tween_hover: Tween
var _base_scale: Vector2 = Vector2.ONE
var _shadow_base_screen_offset: Vector2 = Vector2.ZERO


@export_category("Drag")
# 弹簧强度
@export var drag_stiffness: float = 180.0
# 阻尼
@export var drag_damping: float = 18.0
# 是否允许拖拽
@export var draggable: bool = true
var dragging:bool
var target_position:Vector2
var drag_offset:Vector2
var velocity:Vector2 = Vector2.ZERO

var drag_layer: DraggerLayer
var card_inst: CardInstance


func _ready() -> void:
	_base_scale = scale
	# 每个卡牌实例拥有独立材质；否则一个实例的鼠标倾斜会影响其它卡牌。
	var shader_material := card_texture.material as ShaderMaterial
	if shader_material != null:
		card_texture.material = shader_material.duplicate() as ShaderMaterial

	_shadow_base_screen_offset = shadow.position
	_sync_hover_pivot()
	if not resized.is_connected(_sync_hover_pivot):
		resized.connect(_sync_hover_pivot)
		
	target_position = position
	if card_inst == null:
		card_inst = CardInstance.create_debug_card()
	_sync_rotation_from_card_inst()
	refresh_display()

func _process(delta: float) -> void:
	refresh_shadow()


	var displacement:Vector2 = target_position - position
	
	var force:Vector2 = displacement * drag_stiffness
	
	velocity +=force * delta
	
	velocity *= exp(-drag_damping * delta)
	position += velocity * delta
	

func _sync_hover_pivot() -> void:
	# Control 的默认 pivot_offset 是左上角，缩放时会让卡牌向右下角展开。
	# 将轴固定在中心，悬浮放大和缩小时卡牌保持原地不偏移。
	pivot_offset = size * 0.5


func refresh_shadow(_delta: float = 0.0) -> void:
	if shadow == null:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var viewport_center_x: float = viewport_size.x * 0.5
	var half_viewport_width: float = maxf(viewport_center_x, 1.0)
	var card_transform: Transform2D = get_global_transform_with_canvas()
	var card_screen_center: Vector2 = card_transform * (size * 0.5)
	var horizontal_ratio: float = clampf(
		(card_screen_center.x - viewport_center_x) / half_viewport_width,
		-1.0,
		1.0,
	)
	var desired_screen_offset: Vector2 = Vector2(
		_shadow_base_screen_offset.x - horizontal_ratio * max_offset_shadow,
		_shadow_base_screen_offset.y,
	)
	var card_screen_origin: Vector2 = card_transform * Vector2.ZERO
	shadow.position = (
		card_transform.affine_inverse() * (card_screen_origin + desired_screen_offset)
	)


var rotation_tween: Tween


func rotate_card() -> void:
	if card_inst == null:
		return

	var next_direction: int = posmod(card_inst.direction + 1, 4)
	card_inst.direction = next_direction

	if rotation_tween != null and rotation_tween.is_running():
		rotation_tween.kill()

	var target_rotation: float = float(next_direction * 90)
	while target_rotation <= rotation_degrees:
		target_rotation += 360.0

	rotation_tween = create_tween()
	rotation_tween.set_trans(Tween.TRANS_QUAD)
	rotation_tween.set_ease(Tween.EASE_OUT)
	rotation_tween.tween_property(self, "rotation_degrees", target_rotation, 0.2)
	rotation_tween.tween_callback(
		Callable(self, "_finish_card_rotation").bind(next_direction)
	)


func _finish_card_rotation(expected_direction: int) -> void:
	if card_inst == null or posmod(card_inst.direction, 4) != expected_direction:
		return
	rotation_degrees = float(expected_direction * 90)
	rotation_tween = null


func _sync_rotation_from_card_inst() -> void:
	if card_inst == null:
		return
	if rotation_tween != null and rotation_tween.is_running():
		rotation_tween.kill()
	rotation_tween = null

	# direction 只描述牌桌上的持久化朝向。未入桌卡牌保持默认视觉方向，
	# 避免在 BoardZone 根据当前位置计算候选格前提前旋转根 Control。
	var visual_direction: int = 0
	if card_inst.cur_zone == CardInstance.ZONE.BOARD:
		visual_direction = posmod(card_inst.direction, 4)
	rotation_degrees = float(visual_direction * 90)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(event.position)
			
			else:
				_end_drag()
		elif event.button_index==MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if  dragging:
					rotate_card()
	
	if event is InputEventMouseMotion:
		if dragging:
			_update_drag(event.position)
		else:
			_handle_3D_effect(event)
		
		

func _handle_3D_effect(event:InputEvent)->void:
	var lerp_val_x := clampf(event.position.x / maxf(size.x, 1.0), 0.0, 1.0)
	var lerp_val_y := clampf(event.position.y / maxf(size.y, 1.0), 0.0, 1.0)
	var rot_x := lerpf(-absf(angle_x_max), absf(angle_x_max), lerp_val_x)
	var rot_y := lerpf(absf(angle_y_max), -absf(angle_y_max), lerp_val_y)

	var shader_material := card_texture.material as ShaderMaterial
	if shader_material == null:
		return

	shader_material.set_shader_parameter("x_rot", rot_y)
	shader_material.set_shader_parameter("y_rot", rot_x)
	

func _start_drag(mouse_position: Vector2) -> void:
	if not draggable:
		return

	_hide_hover_info()
	dragging = true
	z_index = 100
	drag_offset = get_global_transform().basis_xform(mouse_position - size * 0.5)
	target_position = position
	if drag_layer and not drag_layer.start_drag(self):
		dragging = false
		z_index = 0
		return

func normalize_card()->void:
	var shader_material := card_texture.material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter("x_rot", 0)
	shader_material.set_shader_parameter("y_rot", 0)
	return

func _update_drag(mouse_position: Vector2) -> void:
	update_drag_target_from_global_pointer(get_global_mouse_position())
	if drag_layer:
		drag_layer.update_drag(self)


func update_drag_target_from_global_pointer(global_pointer: Vector2) -> void:
	var target_global_center: Vector2 = global_pointer - drag_offset
	var parent_canvas := get_parent() as CanvasItem
	if parent_canvas == null:
		target_position = target_global_center - size * 0.5
		return

	var target_parent_center: Vector2 = (
		parent_canvas.get_global_transform().affine_inverse()
		* target_global_center
	)
	target_position = target_parent_center - size * 0.5

func _end_drag()->void:
	if not dragging:
		return
		
	dragging = false
	z_index = 0
	if drag_layer:
		drag_layer.end_drag(self)

func _on_mouse_exited() -> void:
	_hide_hover_info()
	if dragging:
		return 
	if tween_rot and tween_rot.is_running():
		tween_rot.kill()
	var shader_material := card_texture.material as ShaderMaterial
	if shader_material != null:
		tween_rot = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_parallel(true)
		tween_rot.tween_property(shader_material, "shader_parameter/x_rot", 0.0, 0.5)
		tween_rot.tween_property(shader_material, "shader_parameter/y_rot", 0.0, 0.5)

	if tween_hover and tween_hover.is_running():
		tween_hover.kill()
	tween_hover = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween_hover.tween_property(self, "scale", _base_scale, 0.25)
	z_index-=100


func _on_mouse_entered() -> void:
	if dragging:
		return
	_show_hover_info()
	if tween_hover and tween_hover.is_running():
		tween_hover.kill()
	tween_hover = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween_hover.tween_property(self, "scale", _base_scale * 1.2, 0.5)
	z_index+=100
	
func _show_hover_info() -> void:
	if card_inst == null:
		return
	var hover_info := get_tree().get_first_node_in_group("card_hover_info")
	if hover_info != null and hover_info.has_method("show_for_card"):
		hover_info.call("show_for_card", self, card_inst)


func _hide_hover_info() -> void:
	var hover_info := get_tree().get_first_node_in_group("card_hover_info")
	if hover_info != null and hover_info.has_method("hide_for_card"):
		hover_info.call("hide_for_card", self)


func bind_drag_layer(drag_layer:DraggerLayer)->void:
	self.drag_layer=drag_layer


func bind_card_inst(value: CardInstance) -> void:
	card_inst = value
	_sync_rotation_from_card_inst()
	refresh_display()


func get_card_inst() -> CardInstance:
	return card_inst


func refresh_display() -> void:
	if not is_node_ready():
		return

	attack_label.text = str(card_inst.current_points) if card_inst != null else "0"
	defense_label.text = str(card_inst.current_armor) if card_inst != null else "0"
	_update_artwork()


func _update_artwork() -> void:
	artwork.texture = null
	artwork.visible = false
	if card_inst == null or card_inst.card_data == null:
		return

	var artwork_path := card_inst.card_data.artwork_path
	if artwork_path.is_empty() or not ResourceLoader.exists(artwork_path, "Texture2D"):
		return

	var loaded_texture := ResourceLoader.load(artwork_path, "Texture2D") as Texture2D
	if loaded_texture == null:
		return
	artwork.texture = loaded_texture
	artwork.visible = true
