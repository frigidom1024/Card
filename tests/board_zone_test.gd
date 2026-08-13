extends SceneTree

const BOARD_ZONE_SCENE_PATH := "res://scenes/zone/board_zone.tscn"
const HAND_ZONE_SCENE := preload("res://scenes/zone/handzone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const TOLERANCE := 0.01

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(ResourceLoader.exists(BOARD_ZONE_SCENE_PATH), "BoardZone scene exists")
	if not ResourceLoader.exists(BOARD_ZONE_SCENE_PATH):
		quit(1)
		return

	var board_scene := load(BOARD_ZONE_SCENE_PATH) as PackedScene
	var board_node := board_scene.instantiate()
	root.add_child(board_node)
	await process_frame

	_expect(board_node is CardZone, "BoardZone scene implements the CardZone protocol")
	if not board_node is CardZone:
		board_node.free()
		quit(1)
		return

	var board := board_node as CardZone
	for method_name in [
		"set_drag_layer",
		"sync_layout",
		"clear_cards",
		"get_card_cells",
		"get_card_at",
		"get_placement_cell",
		"can_place_card",
		"get_combat_card_chain",
	]:
		_expect(board.has_method(method_name), "BoardZone exposes %s" % method_name)

	var unbound_card := CARD_SCENE.instantiate() as Card
	root.add_child(unbound_card)
	await process_frame
	_move_card_to_anchor(board, unbound_card, Vector2i(4, 4), 0)
	_expect(not board.add_card(unbound_card), "BoardZone rejects a Card without a bound CardInstance")
	unbound_card.free()

	var hand := HAND_ZONE_SCENE.instantiate() as HandZone
	root.add_child(hand)
	await process_frame

	var root_pair := _make_card(CardData.CardType.ROOT, 0, "Root")
	var root_card := root_pair.card as Card
	var root_inst := root_pair.inst as CardInstance
	root.add_child(root_card)
	await process_frame
	_expect(hand.add_card(root_card), "fixture puts ROOT in HandZone")
	_move_card_to_anchor(board, root_card, Vector2i(4, 4), 0)
	hand.start_drag(root_card)
	board.update_drag(root_card)
	_expect(board.can_trans_to_target(root_card), "an unoccupied ROOT can enter an empty BoardZone")
	_expect(board.drag_end_target(root_card, true), "ROOT placement commits in BoardZone")
	_expect(hand.drag_end_source(root_card, true), "HandZone clears ROOT after BoardZone commits")
	_expect(root_card.get_parent() == board, "committed ROOT is reparented to BoardZone")
	_expect(root_card.cur_zone == board, "committed ROOT points at BoardZone")
	_expect(root_inst.cur_zone == CardInstance.ZONE.BOARD, "ROOT CardInstance is marked BOARD")
	_expect(root_inst.battlefield_pos == Vector2i(4, 4), "ROOT CardInstance stores its occupied anchor")
	_expect((board.call("get_card_cells", root_card) as Array) == [Vector2i(4, 4), Vector2i(4, 5)], "vertical ROOT occupies two ordered cells")

	var empty_board_node := board_scene.instantiate()
	root.add_child(empty_board_node)
	await process_frame
	var empty_board := empty_board_node as CardZone
	var normal_first_pair := _make_card(CardData.CardType.NORMAL, 0, "NoRoot")
	var normal_first := normal_first_pair.card as Card
	root.add_child(normal_first)
	await process_frame
	_move_card_to_anchor(empty_board, normal_first, Vector2i(4, 4), 0)
	_expect(not empty_board.add_card(normal_first), "a NORMAL card cannot be the first board card")
	normal_first.free()
	empty_board.free()

	var normal_pair := _make_card(CardData.CardType.NORMAL, 0, "FirstNormal")
	var normal_card := normal_pair.card as Card
	var normal_inst := normal_pair.inst as CardInstance
	root.add_child(normal_card)
	await process_frame
	_expect(hand.add_card(normal_card), "fixture puts NORMAL in HandZone")
	_move_card_to_anchor(board, normal_card, Vector2i(4, 2), 0)
	hand.start_drag(normal_card)
	board.update_drag(normal_card)
	_expect(board.can_trans_to_target(normal_card), "NORMAL can cover the chain tail's forward connection cell")
	_expect(board.drag_end_target(normal_card, true), "connected NORMAL placement commits")
	_expect(hand.drag_end_source(normal_card, true), "HandZone clears connected NORMAL after commit")
	_expect(normal_inst.battlefield_pos == Vector2i(4, 2), "NORMAL stores its occupied anchor")
	_expect(board.call("get_card_at", Vector2i(4, 3)) == normal_card, "BoardZone indexes occupied cells by exact Card")

	var conflict_pair := _make_card(CardData.CardType.ROOT, 0, "Conflict")
	var conflict_card := conflict_pair.card as Card
	root.add_child(conflict_card)
	await process_frame
	_move_card_to_anchor(board, conflict_card, Vector2i(4, 2), 0)
	_expect(not board.add_card(conflict_card), "BoardZone rejects placement over occupied cells")
	conflict_card.free()

	var chain := board.call("get_combat_card_chain") as Array
	_expect(chain.size() == 2, "combat chain reports every committed CardInstance")
	_expect(chain.size() == 2 and chain[0] == root_inst and chain[1] == normal_inst, "combat chain preserves exact CardInstance identity and order")

	board.start_drag(normal_card)
	normal_inst.direction = 1
	_move_card_to_anchor(board, normal_card, Vector2i(4, 3), 1)
	board.update_drag(normal_card)
	_expect(board.can_trans_to_target(normal_card), "the chain tail can move within BoardZone while remaining connected")
	_expect(board.drag_end_target(normal_card, true), "same-zone chain-tail movement commits atomically")
	_expect(board.call("get_card_at", Vector2i(4, 2)) == null, "same-zone movement releases old occupied cells")
	_expect(board.call("get_card_at", Vector2i(5, 3)) == normal_card, "same-zone movement records new occupied cells")
	_expect(normal_inst.battlefield_pos == Vector2i(4, 3), "same-zone movement updates battlefield_pos")
	_expect(normal_inst.direction == 1, "same-zone movement preserves the chosen direction")

	var follower_pair := _make_card(CardData.CardType.NORMAL, 1, "Follower")
	var follower_card := follower_pair.card as Card
	var follower_inst := follower_pair.inst as CardInstance
	root.add_child(follower_card)
	await process_frame
	_move_card_to_anchor(board, follower_card, Vector2i(6, 3), 1)
	_expect(board.add_card(follower_card), "fixture appends a second connected NORMAL")
	_expect((board.call("get_card_cells", follower_card) as Array) == [Vector2i(6, 3), Vector2i(7, 3)], "rotated cards keep stable occupied-cell geometry after snapping")

	var saved_position := normal_card.global_position
	var saved_target := normal_card.target_position
	var saved_anchor := normal_inst.battlefield_pos
	var saved_direction := normal_inst.direction
	board.start_drag(normal_card)
	normal_inst.direction = 2
	normal_card.global_position += Vector2(180.0, 120.0)
	normal_card.target_position = normal_card.position
	board.update_drag(normal_card)
	_expect(not board.can_trans_to_target(normal_card), "a middle chain card cannot be re-placed inside BoardZone")
	_expect(board.drag_end_source(normal_card, false), "cancelled board drag restores its source snapshot")
	_expect(normal_card.global_position.distance_to(saved_position) <= TOLERANCE, "cancel restores the middle card position")
	_expect(normal_card.target_position.distance_to(saved_target) <= TOLERANCE, "cancel restores the middle card target position")
	_expect(normal_inst.battlefield_pos == saved_anchor, "cancel preserves battlefield_pos")
	_expect(normal_inst.direction == saved_direction, "cancel preserves direction")
	_expect(board.get_cards() == [root_card, normal_card, follower_card], "cancel preserves the complete board chain")
	_expect(board.call("get_card_at", Vector2i(6, 3)) == follower_card, "cancel preserves follower occupancy")

	var receiving_hand := HAND_ZONE_SCENE.instantiate() as HandZone
	root.add_child(receiving_hand)
	await process_frame
	board.start_drag(normal_card)
	receiving_hand.update_drag(normal_card)
	_expect(receiving_hand.drag_end_target(normal_card, true), "HandZone accepts a dragged middle board card")
	_expect(board.drag_end_source(normal_card, true), "BoardZone commits middle-card removal after HandZone accepts it")
	_expect(board.get_cards() == [root_card], "middle-card removal returns the entire following chain segment")
	_expect(receiving_hand.get_cards().has(normal_card), "dragged middle card remains in the target HandZone")
	_expect(receiving_hand.get_cards().has(follower_card), "every follower is moved to the same HandZone")
	_expect(normal_inst.cur_zone == CardInstance.ZONE.HAND and follower_inst.cur_zone == CardInstance.ZONE.HAND, "returned CardInstances are marked HAND")
	_expect(normal_inst.battlefield_pos == Vector2i(-1, -1) and follower_inst.battlefield_pos == Vector2i(-1, -1), "returned CardInstances clear battlefield_pos")
	_expect(normal_inst.direction == 0 and follower_inst.direction == 0, "returned board segment resets direction")
	_expect(board.call("get_card_at", Vector2i(4, 3)) == null and board.call("get_card_at", Vector2i(6, 3)) == null, "returned board segment releases all occupied cells")

	var drag_layer := DraggerLayer.new()
	var replacement_layer := DraggerLayer.new()
	root.add_child(drag_layer)
	root.add_child(replacement_layer)
	board.call("set_drag_layer", drag_layer)
	_expect(drag_layer.get_registered_zones().has(board), "BoardZone registers itself with the current DraggerLayer")
	_expect(root_card.drag_layer == drag_layer, "BoardZone binds existing cards to the current DraggerLayer")
	board.call("set_drag_layer", replacement_layer)
	_expect(not drag_layer.get_registered_zones().has(board), "BoardZone unregisters from the previous DraggerLayer")
	_expect(replacement_layer.get_registered_zones().has(board), "BoardZone registers with the replacement DraggerLayer")
	_expect(root_card.drag_layer == replacement_layer, "BoardZone rebinds existing cards to the replacement DraggerLayer")
	board.call("set_drag_layer", null)
	_expect(not replacement_layer.get_registered_zones().has(board), "clearing the DraggerLayer unregisters BoardZone")
	_expect(root_card.drag_layer == null, "clearing the DraggerLayer unbinds existing cards")

	hand.free()
	receiving_hand.free()
	board.free()
	drag_layer.free()
	replacement_layer.free()
	quit(1 if _failures > 0 else 0)


func _make_card(card_type: CardData.CardType, direction: int, card_name: String) -> Dictionary:
	var data := CardData.new()
	data.card_type = card_type
	data.card_name = card_name
	var inst := CardInstance.new(data)
	inst.direction = direction
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(inst)
	return {"card": card, "inst": inst}


func _move_card_to_anchor(board: CardZone, card: Card, anchor: Vector2i, direction: int) -> void:
	var background := board.get_node("BackGround") as BoardZoneBG
	var cell_size := background.cell_size
	var local_center: Vector2
	if posmod(direction, 4) % 2 == 0:
		local_center = Vector2(
			(float(anchor.x) + 0.5) * cell_size,
			(float(anchor.y) + 1.0) * cell_size
		)
	else:
		local_center = Vector2(
			(float(anchor.x) + 1.0) * cell_size,
			(float(anchor.y) + 0.5) * cell_size
		)
	var center := background.to_global(local_center)
	card.global_position = center - card.size * 0.5
	card.target_position = card.position
	var inst := card.get_card_inst()
	if inst != null:
		inst.direction = direction


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
