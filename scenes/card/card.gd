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

var drag_layer:DraggerLayer
var cur_zone:CardZone
var card_inst: CardInstance


func _ready() -> void:
	# 每个卡牌实例拥有独立材质；否则一个实例的鼠标倾斜会影响其它卡牌。
	var shader_material := card_texture.material as ShaderMaterial
	if shader_material != null:
		card_texture.material = shader_material.duplicate() as ShaderMaterial

	_sync_hover_pivot()
	if not resized.is_connected(_sync_hover_pivot):
		resized.connect(_sync_hover_pivot)
		
	target_position  = position
	refresh_display()

func _process(delta: float) -> void:
	refresh_shadow(delta)


	var displacement:Vector2 = target_position - position
	
	var force:Vector2 = displacement * drag_stiffness
	
	velocity +=force * delta
	
	velocity *= exp(-drag_damping * delta)
	position += velocity * delta
	

func _sync_hover_pivot() -> void:
	# Control 的默认 pivot_offset 是左上角，缩放时会让卡牌向右下角展开。
	# 将轴固定在中心，悬浮放大和缩小时卡牌保持原地不偏移。
	pivot_offset = size * 0.5


func refresh_shadow(delta:float)->void:
	var center:Vector2 = get_viewport_rect().size/2
	var distance:float = global_position.x-center.x
	
	shadow.position.x = lerp(0.0,-sign(distance)*max_offset_shadow,abs(distance/center.x))
	

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(event.position)
			
			else:
				_end_drag()
	
	
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
	dragging = true
	z_index = 100
	drag_offset = get_global_mouse_position() - global_position
	target_position = position
	if drag_layer:
		drag_layer.start_drag(self)

	
func _update_drag(mouse_postion:Vector2)->void:
	target_position= get_global_mouse_position()-drag_offset
	if drag_layer:
		drag_layer.update_drag(self)

func _end_drag()->void:
	if not dragging:
		return
		
	dragging = false
	z_index = 0
	if drag_layer:
		drag_layer.end_drag(self)

func _on_mouse_exited() -> void:
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
	tween_hover.tween_property(self, "scale", Vector2.ONE, 0.25)


func _on_mouse_entered() -> void:
	if dragging:
		return 
	if tween_hover and tween_hover.is_running():
		tween_hover.kill()
	tween_hover = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween_hover.tween_property(self, "scale", Vector2(1.2, 1.2), 0.5)
	
func bind_drag_layer(drag_layer:DraggerLayer)->void:
	self.drag_layer=drag_layer


func bind_card_inst(value: CardInstance) -> void:
	card_inst = value
	if is_node_ready():
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
