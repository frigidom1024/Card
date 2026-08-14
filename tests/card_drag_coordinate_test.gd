extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")
const TOLERANCE := 0.01

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var zone := Control.new()
	zone.position = Vector2(383.0, 166.0)
	zone.size = Vector2(1126.0, 218.0)
	root.add_child(zone)

	var card := CARD_SCENE.instantiate() as Card
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.position = Vector2(100.0, 20.0)
	zone.add_child(card)
	await process_frame

	var card_data := CardData.new()
	card_data.max_points = 1
	card_data.armor = 0
	var card_inst := CardInstance.new(card_data)
	card.bind_card_inst(card_inst)
	_expect(card.get_card_inst() == card_inst, "drag tests bind the exact CardInstance")

	var initial_pointer := card.global_position + Vector2(20.0, 40.0)
	card.drag_offset = initial_pointer - card.global_position
	_expect(card.has_method("update_drag_target_from_global_pointer"), "Card converts a global drag pointer into its parent-local target position")

	if card.has_method("update_drag_target_from_global_pointer"):
		card.update_drag_target_from_global_pointer(initial_pointer)
		_expect(card.target_position.distance_to(card.position) <= TOLERANCE, "drag target stays at the Card local position when pointer has not moved")

		var moved_pointer := initial_pointer + Vector2(120.0, -36.0)
		card.update_drag_target_from_global_pointer(moved_pointer)
		var expected_target: Vector2 = zone.get_global_transform().affine_inverse() * (moved_pointer - card.drag_offset)
		_expect(card.target_position.distance_to(expected_target) <= TOLERANCE, "drag target remains parent-local after moving HandZone away from the origin")

	card.free()
	zone.free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
