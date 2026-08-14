extends SceneTree

const TEST_SCENE := preload("res://scenes/drag_layer/test.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var page := TEST_SCENE.instantiate()
	root.add_child(page)
	await process_frame
	await process_frame

	var dragger := page.get_node("DraggerLayer") as DraggerLayer
	var first_hand := page.get_node("Handzone") as HandZone
	var second_hand := page.get_node("Handzone2") as HandZone
	var board := page.get_node("BoardZone") as BoardZone
	var root_card := page.get_node("Handzone/Card2") as Card
	var normal_card := page.get_node("Handzone2/Card2") as Card

	_expect(dragger != null and board != null, "drag test scene exposes DraggerLayer and BoardZone")
	_expect(
		dragger.get_registered_zones().has(first_hand)
		and dragger.get_registered_zones().has(second_hand)
		and dragger.get_registered_zones().has(board),
		"drag test scene registers both HandZones and BoardZone"
	)
	_expect(board.get("_drag_layer") == dragger, "BoardZone is assembled through set_drag_layer")
	_expect(
		root_card.get_card_inst() != null
		and root_card.get_card_inst().card_data.card_type == CardData.CardType.ROOT,
		"first test Card is explicitly bound to a ROOT CardInstance"
	)
	_expect(
		normal_card.get_card_inst() != null
		and normal_card.get_card_inst().card_data.card_type == CardData.CardType.NORMAL,
		"second test Card is explicitly bound to a NORMAL CardInstance"
	)
	_expect(
		root_card.drag_layer == dragger and normal_card.drag_layer == dragger,
		"test Cards are bound to the shared DraggerLayer"
	)

	_move_card_to_anchor(board, root_card, Vector2i(4, 4), 0)
	_expect(dragger.start_drag(root_card), "ROOT starts dragging from its HandZone")
	_expect(first_hand.owns_card(root_card), "drag start keeps stable HandZone membership")
	_expect(dragger.end_drag(root_card), "ROOT drag completes through the real DraggerLayer")
	_expect(board.owns_card(root_card), "BoardZone accepts the ROOT from the test scene")
	_expect(
		root_card.get_card_inst().cur_zone == CardInstance.ZONE.BOARD,
		"accepted ROOT updates its CardInstance to BOARD"
	)

	page.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _move_card_to_anchor(
	board: BoardZone,
	card: Card,
	anchor: Vector2i,
	direction: int
) -> void:
	var background := board.back_ground
	var local_center := Vector2(
		(float(anchor.x) + 0.5) * background.cell_size,
		(float(anchor.y) + 1.0) * background.cell_size
	)
	card.get_card_inst().direction = direction
	card.global_position = background.to_global(local_center) - card.size * 0.5
	card.target_position = card.position


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
