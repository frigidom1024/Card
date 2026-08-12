extends SceneTree

const CardScene := preload("res://scenes/card/card2.tscn")
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var card := CardScene.instantiate() as Button
	root.add_child(card)
	await process_frame

	var card_texture := card.get_node("CardTexture") as SubViewportContainer
	var material := card_texture.material as ShaderMaterial
	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.position = Vector2(card.size.x, 0.0)
	card._on_gui_input(mouse_motion)

	_expect(absf(float(material.get_shader_parameter("x_rot"))) <= card.angle_x_max, "top edge x rotation stays within configured degree limit")
	_expect(absf(float(material.get_shader_parameter("y_rot"))) <= card.angle_y_max, "right edge y rotation stays within configured degree limit")

	card.free()
	quit(1 if _failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
