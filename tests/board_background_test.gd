extends SceneTree

const BoardScene := preload("res://scenes/game/board.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_board_scene_contains_node2d_board_background()
	_test_default_board_dimensions_are_synchronized_to_background()
	_test_public_layout_sync_updates_resized_background()
	_test_drop_detector_uses_only_logical_board_dimensions()
	_test_background_exposes_enabled_dashed_grid_configuration()
	_test_invalid_layout_values_are_clamped_before_sync()
	quit(1 if _failure_count > 0 else 0)


func _test_board_scene_contains_node2d_board_background() -> void:
	var board := _make_board()
	_expect(board is Node2D, "Board remains a Node2D")

	var background := board.get_node_or_null("BoardBackground")
	_expect(background != null, "Board contains a BoardBackground child")
	if background != null:
		_expect(background is BoardBackground, "BoardBackground uses the BoardBackground type")
		_expect(background is Node2D, "BoardBackground is a Node2D draw node")
		_expect(not background is Control, "BoardBackground does not use a Control that could intercept GUI input")
		if background is BoardBackground:
			var typed_background := background as BoardBackground
			_expect(
				typed_background.z_index == RenderPriority.BOARD_BACKGROUND,
				"BoardBackground uses the BOARD_BACKGROUND render priority"
			)
			var drop_detector := board.get_node_or_null("DropDetector")
			_expect(drop_detector != null, "Board contains a DropDetector child")
			if drop_detector != null:
				_expect(
					typed_background.get_index() < drop_detector.get_index(),
					"BoardBackground is ordered before DropDetector"
				)
		_expect(background.get_script() is Script, "BoardBackground has a script")
	board.queue_free()


func _test_default_board_dimensions_are_synchronized_to_background() -> void:
	var board := _make_board()
	var background := _background_or_fail(board)
	if background == null:
		board.queue_free()
		return

	var expected_board_size := Vector2(board.width * board.cell_size, board.height * board.cell_size)
	_expect(background.board_size == expected_board_size, "background board_size matches Board defaults")
	_expect(background.cell_size == board.cell_size, "background cell_size matches Board defaults")
	_expect(background.grid_width == board.width, "background grid_width matches Board defaults")
	_expect(background.grid_height == board.height, "background grid_height matches Board defaults")
	board.queue_free()


func _test_public_layout_sync_updates_resized_background() -> void:
	var board := _make_board()
	board.width = 7
	board.height = 5
	board.cell_size = 96

	_expect(board.has_method(&"sync_layout"), "Board exposes sync_layout() as the public layout synchronization API")
	if board.has_method(&"sync_layout"):
		board.call(&"sync_layout")

	var background := _background_or_fail(board)
	if background == null:
		board.queue_free()
		return

	var expected_board_size := Vector2(board.width * board.cell_size, board.height * board.cell_size)
	_expect(background.board_size == expected_board_size, "sync_layout() updates background board_size")
	_expect(background.cell_size == board.cell_size, "sync_layout() updates background cell_size")
	_expect(background.grid_width == board.width, "sync_layout() updates background grid_width")
	_expect(background.grid_height == board.height, "sync_layout() updates background grid_height")
	board.queue_free()


func _test_drop_detector_uses_only_logical_board_dimensions() -> void:
	var board := _make_board()
	board.width = 7
	board.height = 5
	board.cell_size = 96

	_expect(board.has_method(&"sync_layout"), "resizing the Board uses its public sync_layout() API")
	if board.has_method(&"sync_layout"):
		board.call(&"sync_layout")

	var expected_logic_size := Vector2(board.width * board.cell_size, board.height * board.cell_size)
	var collision_shape := board.get_node_or_null("DropDetector/CollisionShape2D") as CollisionShape2D
	_expect(collision_shape != null, "Board keeps DropDetector/CollisionShape2D")
	if collision_shape != null:
		_expect(collision_shape.shape is RectangleShape2D, "DropDetector uses a rectangular logical-board collision shape")
		if collision_shape.shape is RectangleShape2D:
			_expect(
				(collision_shape.shape as RectangleShape2D).size == expected_logic_size,
				"DropDetector size excludes BoardBackground visual padding"
			)
		_expect(
			collision_shape.position == expected_logic_size / 2.0,
			"DropDetector stays centered over only the logical board"
		)
	board.queue_free()


func _test_background_exposes_enabled_dashed_grid_configuration() -> void:
	var board := _make_board()
	var background := _background_or_fail(board)
	if background == null:
		board.queue_free()
		return

	_expect(background.board_padding is Vector2, "background exposes Vector2 board_padding")
	_expect(
		background.board_padding.x > 0.0 and background.board_padding.y > 0.0,
		"background board_padding has positive x and y"
	)
	_expect(background.grid_line_width > 0.0, "background exposes a positive grid_line_width")
	_expect(background.grid_dash_length > 0.0, "background exposes a positive grid_dash_length")
	_expect(background.grid_gap_length > 0.0, "background exposes a positive grid_gap_length")
	_expect(
		background.board_panel_color.a > 0.0 and background.board_panel_color.a < 1.0,
		"background board_panel_color alpha is translucent"
	)
	_expect(
		background.grid_line_color.a > 0.0 and background.grid_line_color.a < 1.0,
		"background grid_line_color alpha is translucent"
	)
	board.queue_free()


func _test_invalid_layout_values_are_clamped_before_sync() -> void:
	var board := _make_board()
	board.width = 0
	board.height = -4
	board.cell_size = 0
	board.sync_layout()

	_expect(board.width == 1, "sync_layout clamps width to a drawable board")
	_expect(board.height == 1, "sync_layout clamps height to a drawable board")
	_expect(board.cell_size == 1, "sync_layout clamps cell_size to a drawable board")

	var background := _background_or_fail(board)
	if background != null:
		_expect(background.board_size == Vector2.ONE, "clamped layout gives BoardBackground a valid size")
	var collision_shape := board.get_node_or_null("DropDetector/CollisionShape2D") as CollisionShape2D
	if collision_shape != null and collision_shape.shape is RectangleShape2D:
		_expect((collision_shape.shape as RectangleShape2D).size == Vector2.ONE, "clamped layout gives DropDetector a valid size")
	board.queue_free()


func _make_board() -> Board:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	return board


func _background_or_fail(board: Board) -> BoardBackground:
	var background := board.get_node_or_null("BoardBackground") as BoardBackground
	_expect(background != null, "Board contains a BoardBackground child")
	return background


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)

