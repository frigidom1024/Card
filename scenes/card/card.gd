extends Button

@onready var card_texture: Control = $CardTexture
@onready var shadow:Control = $Shadow
@export var angle_x_max: float = 8.0
@export var angle_y_max: float = 8.0
@export var max_offset_shadow:float=6.0

var tween_rot: Tween
var tween_hover: Tween


func _ready() -> void:
	# 每个卡牌实例拥有独立材质；否则一个实例的鼠标倾斜会影响其它卡牌。
	var shader_material := card_texture.material as ShaderMaterial
	if shader_material != null:
		card_texture.material = shader_material.duplicate() as ShaderMaterial

	_sync_hover_pivot()
	if not resized.is_connected(_sync_hover_pivot):
		resized.connect(_sync_hover_pivot)

func _process(delta: float) -> void:
	refresh_shadow(delta)

func _sync_hover_pivot() -> void:
	# Control 的默认 pivot_offset 是左上角，缩放时会让卡牌向右下角展开。
	# 将轴固定在中心，悬浮放大和缩小时卡牌保持原地不偏移。
	pivot_offset = size * 0.5


func refresh_shadow(delta:float)->void:
	var center:Vector2 = get_viewport_rect().size/2
	var distance:float = global_position.x-center.x
	
	shadow.position.x = lerp(0.0,-sign(distance)*max_offset_shadow,abs(distance/center.x))
	

func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return

	var lerp_val_x := clampf(event.position.x / maxf(size.x, 1.0), 0.0, 1.0)
	var lerp_val_y := clampf(event.position.y / maxf(size.y, 1.0), 0.0, 1.0)
	var rot_x := lerpf(-absf(angle_x_max), absf(angle_x_max), lerp_val_y)
	var rot_y := lerpf(absf(angle_y_max), -absf(angle_y_max), lerp_val_x)

	var shader_material := card_texture.material as ShaderMaterial
	if shader_material == null:
		return

	shader_material.set_shader_parameter("x_rot", rot_x)
	shader_material.set_shader_parameter("y_rot", rot_y)


func _on_mouse_exited() -> void:
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
	if tween_hover and tween_hover.is_running():
		tween_hover.kill()
	tween_hover = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween_hover.tween_property(self, "scale", Vector2(1.2, 1.2), 0.5)
