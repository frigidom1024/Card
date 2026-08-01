extends SceneTree

const LayoutConfigScript = preload("res://scripts/game/layout_config.gd")
const BoardScene = preload("res://scenes/game/board.tscn")
const HandAreaScript = preload("res://scripts/game/hand.gd")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")

var _failure_count := 0

func _init() -> void:
	_expect(LayoutConfigScript.CELL_SIZE == 86, "CELL_SIZE is 86")
	_expect(LayoutConfigScript.CARD_MARGIN == 6, "CARD_MARGIN is 6")
	_expect(LayoutConfigScript.CARD_W == 80, "CARD_W derives from CELL_SIZE minus margin")
	_expect(LayoutConfigScript.CARD_H == 166, "CARD_H covers two cells minus margin")
	_expect(LayoutConfigScript.HAND_SPACING == 30, "HAND_SPACING derives from CELL_SIZE")
	_expect(LayoutConfigScript.HAND_STEP == 110, "HAND_STEP is card width plus spacing")
	_expect(
		LayoutConfigScript.CARD_H + LayoutConfigScript.CARD_MARGIN == LayoutConfigScript.CELL_SIZE * 2,
		"card height plus margin fills exactly two cells"
	)

	var card_rect := LayoutConfigScript.card_view_rect(86)
	_expect(card_rect.size == Vector2(80, 166), "card view rect size follows cell size")
	_expect(card_rect.position == Vector2(-40, -83), "card view rect is centered on the entity")

	var board_pos := LayoutConfigScript.board_origin(Vector2(1600, 900), 10, 8, 86)
	_expect(board_pos == Vector2(370, 16), "board origin centers the 860x688 grid horizontally")

	var hand_pos := LayoutConfigScript.hand_origin(Vector2(1600, 900))
	_expect(hand_pos == Vector2(800, 804), "hand origin centers and hugs the bottom")

	# 棋盘底与手牌顶不重叠（至少留 10px）
	var board_bottom := board_pos.y + 8 * 86
	var hand_top := hand_pos.y - 86
	_expect(board_bottom + 10 <= hand_top, "board bottom clears the hand top")

	var board := BoardScene.instantiate() as Board
	_expect(board.cell_size == LayoutConfigScript.CELL_SIZE, "board defaults to the configured cell size")
	board.free()

	call_deferred("_run_deferred_tests")

func _run_deferred_tests() -> void:
	_test_board_drop_detector()
	_test_card_entity_sizing()
	_finish_tests()

func _test_board_drop_detector() -> void:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	var shape_node := board.get_node_or_null("DropDetector/CollisionShape2D") as CollisionShape2D
	var shape := shape_node.shape as RectangleShape2D
	_expect(shape != null and shape.size == Vector2(860, 688), "drop detector matches the resized grid")
	_expect(shape_node.position == Vector2(430, 344), "drop detector centers on the resized grid")
	board.queue_free()

func _test_card_entity_sizing() -> void:
	var card := CardEntityScene.instantiate() as CardEntity
	root.add_child(card)
	var shape := (card.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	_expect(shape != null and shape.size == Vector2(86, 172), "card collision box covers two resized cells")
	var card_view := card.get_node("CardView") as Control
	_expect(card_view.size == Vector2(80, 166), "card view derives from the configured cell size")
	card.queue_free()

func _finish_tests() -> void:
	quit(1 if _failure_count > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
