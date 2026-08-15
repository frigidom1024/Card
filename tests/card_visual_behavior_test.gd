extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_binding_syncs_board_visual_direction()
	await _test_binding_does_not_apply_board_rotation_before_placement()
	await _test_rotation_updates_instance_and_wraps_clockwise()
	await _test_shadow_uses_bounded_screen_space_offset_after_rotation()
	await _test_rotated_drag_keeps_visual_center_aligned_with_pointer()
	quit(1 if _failures > 0 else 0)


func _test_binding_syncs_board_visual_direction() -> void:
	var instance := CardInstance.new(CardData.new())
	instance.cur_zone = CardInstance.ZONE.BOARD
	instance.direction = 3
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(instance)
	root.add_child(card)
	await process_frame

	_expect(
		is_equal_approx(card.rotation_degrees, 270.0),
		"binding a BOARD CardInstance restores its direction to the card visual",
	)

	card.free()
	await process_frame


func _test_binding_does_not_apply_board_rotation_before_placement() -> void:
	var instance := CardInstance.new(CardData.new())
	instance.cur_zone = CardInstance.ZONE.DRAW
	instance.direction = 3
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(instance)
	root.add_child(card)
	await process_frame

	_expect(
		is_zero_approx(card.rotation_degrees),
		"binding a non-board CardInstance keeps the pre-placement visual unrotated",
	)

	card.free()
	await process_frame


func _test_rotation_updates_instance_and_wraps_clockwise() -> void:
	var instance := CardInstance.new(CardData.new())
	instance.direction = 3
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(instance)
	root.add_child(card)
	await process_frame
	card.rotation_degrees = 270.0

	card.rotate_card()
	_expect(instance.direction == 0, "rotating writes the next direction to CardInstance")

	await create_timer(0.05).timeout
	_expect(
		card.rotation_degrees > 270.0,
		"wrapping from direction 3 to 0 continues clockwise toward 360 degrees",
	)

	await create_timer(0.25).timeout
	_expect(
		is_zero_approx(card.rotation_degrees),
		"completed rotation normalizes the visual angle to CardInstance direction",
	)

	card.free()
	await process_frame


func _test_shadow_uses_bounded_screen_space_offset_after_rotation() -> void:
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(CardInstance.new(CardData.new()))
	root.add_child(card)
	await process_frame

	var viewport_size := root.get_visible_rect().size
	card.position = Vector2(viewport_size.x * 0.75, viewport_size.y * 0.5)
	card.target_position = card.position
	card.rotation_degrees = 90.0
	card.refresh_shadow(0.0)

	var rotated_offset := _get_shadow_screen_offset(card)
	_expect(rotated_offset.x < 0.0, "a card right of center casts its shadow toward screen-left")
	_expect(rotated_offset.y > 0.0, "card rotation does not rotate the shadow's downward screen offset")

	card.rotation_degrees = 0.0
	card.position = Vector2(viewport_size.x * 2.0, viewport_size.y * 0.5)
	card.target_position = card.position
	card.refresh_shadow(0.0)
	var clamped_offset := _get_shadow_screen_offset(card)
	_expect(
		absf(clamped_offset.x) <= card.max_offset_shadow + 0.01,
		"shadow horizontal offset stays within max_offset_shadow outside the viewport",
	)

	card.free()
	await process_frame


func _test_rotated_drag_keeps_visual_center_aligned_with_pointer() -> void:
	var parent := Control.new()
	root.add_child(parent)
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(CardInstance.new(CardData.new()))
	parent.add_child(card)
	await process_frame

	card.position = Vector2(100.0, 100.0)
	card.target_position = card.position
	card.rotation_degrees = 90.0
	var local_pointer_offset := Vector2(8.0, 12.0)
	var pointer_offset := Vector2(-12.0, 8.0)
	card._start_drag(card.size * 0.5 + local_pointer_offset)
	_expect(
		card.drag_offset.is_equal_approx(pointer_offset),
		"a rotated drag stores its pointer offset from the visual center",
	)

	var expected_center := Vector2(500.0, 300.0)
	card.update_drag_target_from_global_pointer(expected_center + pointer_offset)
	card.position = card.target_position
	var actual_center: Vector2 = (
		card.get_global_transform_with_canvas() * (card.size * 0.5)
	)

	_expect(
		actual_center.is_equal_approx(expected_center),
		"a rotated card keeps its visual center aligned while dragging",
	)

	parent.free()
	await process_frame


func _get_shadow_screen_offset(card: Card) -> Vector2:
	var card_origin := card.get_global_transform_with_canvas() * Vector2.ZERO
	var shadow_origin := card.shadow.get_global_transform_with_canvas() * Vector2.ZERO
	return shadow_origin - card_origin


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
