extends SceneTree

const TEST_SCENE := preload("res://scenes/drag_layer/test.tscn")
const TOLERANCE := 0.01

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var test_scene := TEST_SCENE.instantiate() as Node2D
	root.add_child(test_scene)
	await process_frame

	var hand_zone_1 := test_scene.get_node("Handzone") as HandZone
	var hand_zone_2 := test_scene.get_node("Handzone2") as HandZone
	var card := test_scene.get_node("Handzone/Card") as Card
	_expect(hand_zone_1 != null and hand_zone_2 != null and card != null, "drag-layer test scene exposes two HandZones and a draggable Card")
	_expect(test_scene.has_method("_on_card_dragging_end"), "test scene coordinates Card drop events")
	if hand_zone_1 == null or hand_zone_2 == null or card == null:
		test_scene.free()
		quit(1)
		return

	var target_point := hand_zone_2.global_position + hand_zone_2.size * 0.5
	card.global_position = target_point
	card.target_position = card.position
	card.dragging_end.emit(card)

	_expect(card.get_parent() == hand_zone_2, "dropping a Card inside another HandZone reparents it to that HandZone")
	_expect(hand_zone_2.cards.has(card), "destination HandZone records the dropped Card")
	_expect(not hand_zone_1.cards.has(card), "source HandZone no longer records a transferred Card")
	_expect(card.global_position.distance_to(target_point) <= TOLERANCE, "reparenting preserves the Card global drop position")

	var outside_point := Vector2(80.0, 450.0)
	card.global_position = outside_point
	card.target_position = card.position
	card.dragging_end.emit(card)
	_expect(card.get_parent() == hand_zone_2, "dropping outside every HandZone keeps the Card in its current parent")

	test_scene.free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)