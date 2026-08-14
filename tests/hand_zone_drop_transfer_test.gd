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
	var drag_layer := test_scene.get_node("DraggerLayer") as DraggerLayer
	var card := test_scene.get_node("Handzone/Card2") as Card
	_expect(
		hand_zone_1 != null and hand_zone_2 != null and drag_layer != null and card != null,
		"drag-layer test scene exposes two HandZones, a DraggerLayer, and a draggable Card"
	)
	if hand_zone_1 == null or hand_zone_2 == null or drag_layer == null or card == null:
		test_scene.queue_free()
		await process_frame
		quit(1)
		return

	card.dragging = true
	_expect(drag_layer.start_drag(card), "DraggerLayer starts the HandZone transfer")
	_expect(hand_zone_1.owns_card(card), "source HandZone keeps stable ownership while dragging")

	var target_point := hand_zone_2.get_global_rect().get_center()
	card.global_position = target_point - card.size * 0.5
	card.target_position = card.position
	drag_layer.update_drag(card)
	var drop_global_center := (
		card.get_global_transform_with_canvas() * (card.size * 0.5)
	)
	card.dragging = false
	_expect(drag_layer.end_drag(card), "DraggerLayer completes the HandZone transfer")

	_expect(
		card.get_parent() == hand_zone_2,
		"dropping a Card inside another HandZone reparents it to that HandZone"
	)
	_expect(hand_zone_2.owns_card(card), "destination HandZone records the dropped Card")
	_expect(not hand_zone_1.owns_card(card), "source HandZone no longer records a transferred Card")
	var current_global_center := (
		card.get_global_transform_with_canvas() * (card.size * 0.5)
	)
	_expect(
		current_global_center.distance_to(drop_global_center) <= TOLERANCE,
		"reparenting preserves the Card visual drop position"
	)

	card.dragging = true
	_expect(drag_layer.start_drag(card), "DraggerLayer starts a cancellable drag")
	_expect(
		hand_zone_2.owns_card(card),
		"current HandZone keeps stable ownership during the cancelled drag"
	)
	card.global_position = Vector2(3000.0, 1500.0)
	card.target_position = card.position
	drag_layer.update_drag(card)
	card.dragging = false
	_expect(drag_layer.end_drag(card), "dropping outside completes the cancelled drag lifecycle")
	_expect(
		card.get_parent() == hand_zone_2,
		"dropping outside every HandZone keeps the Card in its current parent"
	)
	_expect(hand_zone_2.owns_card(card), "cancelled drag keeps the Card in its source HandZone")

	test_scene.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)