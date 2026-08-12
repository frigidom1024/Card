extends SceneTree

const CardScene := preload("res://scenes/card/card.tscn")

var _failure_count := 0

func _init() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var card := CardScene.instantiate() as Button
	root.add_child(card)
	await process_frame

	var card_texture := card.get_node("CardTexture")
	card_texture.size = Vector2(100.0, 200.0)
	await process_frame

	var shader_material := card_texture.material as ShaderMaterial
	_expect(shader_material != null, "composed card keeps its perspective ShaderMaterial")
	if shader_material == null:
		quit(1)
		return

	card_texture._set_tilt_from_local_position(Vector2(50.0, 100.0))
	_expect(is_zero_approx(float(shader_material.get_shader_parameter("x_rot"))), "center pointer produces zero x rotation")
	_expect(is_zero_approx(float(shader_material.get_shader_parameter("y_rot"))), "center pointer produces zero y rotation")

	card_texture._set_tilt_from_local_position(Vector2(-100.0, 100.0))
	_expect(is_zero_approx(float(shader_material.get_shader_parameter("x_rot"))), "pointer outside left edge does not trigger x rotation")
	_expect(is_zero_approx(float(shader_material.get_shader_parameter("y_rot"))), "pointer outside left edge does not trigger y rotation")

	card_texture._set_tilt_from_local_position(Vector2(100.0, 0.0))
	_expect(abs(float(shader_material.get_shader_parameter("x_rot"))) <= card_texture.angle_x_max, "x rotation never exceeds configured maximum")
	_expect(abs(float(shader_material.get_shader_parameter("y_rot"))) <= card_texture.angle_y_max, "y rotation never exceeds configured maximum")

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(-10.0, 100.0)
	card_texture._on_gui_input(motion)
	_expect(is_zero_approx(float(shader_material.get_shader_parameter("x_rot"))), "gui input outside card does not apply x rotation")
	_expect(is_zero_approx(float(shader_material.get_shader_parameter("y_rot"))), "gui input outside card does not apply y rotation")

	card_texture._reset_tilt()
	_expect(is_zero_approx(float(shader_material.get_shader_parameter("x_rot"))), "reset clears x rotation")
	_expect(is_zero_approx(float(shader_material.get_shader_parameter("y_rot"))), "reset clears y rotation")

	card.free()
	quit(1 if _failure_count > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
