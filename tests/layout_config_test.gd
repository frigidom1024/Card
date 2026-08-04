extends SceneTree

const LayoutConfigScript = preload("res://scripts/game/layout_config.gd")
const GameplayCanvasScript = preload("res://scripts/game/gameplay_canvas.gd")
const BoardScene = preload("res://scenes/game/board.tscn")
const HandAreaScript = preload("res://scripts/game/hand.gd")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const CardViewScene = preload("res://scenes/card_view/card_view.tscn")
const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0

class ViewportSizeChangedWaiter extends RefCounted:
	signal completed
	var _completed := false

	func bind(viewport: SubViewport) -> void:
		viewport.size_changed.connect(_on_size_changed, CONNECT_ONE_SHOT)

	func wait() -> void:
		if not _completed:
			await completed

	func _on_size_changed() -> void:
		_completed = true
		completed.emit()

func _init() -> void:
	_expect(LayoutConfigScript.DESIGN_VIEWPORT_SIZE == Vector2(1920, 1080), "layout uses the 1920x1080 design viewport")
	_expect(LayoutConfigScript.CELL_SIZE == 104, "CELL_SIZE is 104 at the 1920x1080 baseline")
	_expect(LayoutConfigScript.CARD_MARGIN == 20, "CARD_MARGIN preserves the configured card inset")
	_expect(LayoutConfigScript.CARD_W == 84, "CARD_W derives from CELL_SIZE minus margin")
	_expect(LayoutConfigScript.CARD_H == 188, "CARD_H covers two cells minus margin")
	_expect(LayoutConfigScript.HAND_SPACING == 36, "HAND_SPACING derives from CELL_SIZE")
	_expect(LayoutConfigScript.HAND_STEP == 120, "HAND_STEP is card width plus spacing")
	_expect(
		LayoutConfigScript.CARD_H + LayoutConfigScript.CARD_MARGIN == LayoutConfigScript.CELL_SIZE * 2,
		"card height plus margin fills exactly two cells"
	)

	var card_rect := LayoutConfigScript.card_view_rect(104)
	_expect(card_rect.size == Vector2(84, 188), "card view rect size follows cell size")
	_expect(card_rect.position == Vector2(-42, -94), "card view rect is centered on the entity")

	var board_pos := LayoutConfigScript.board_origin(Vector2(1920, 1080), 10, 8, 104)
	_expect(board_pos == Vector2(440, 19), "board origin centers the 1040x832 grid horizontally")

	var hand_pos := LayoutConfigScript.hand_origin(Vector2(1920, 1080))
	_expect(hand_pos == Vector2(960, 965), "hand origin centers and hugs the bottom")

	# 棋盘底与手牌顶不重叠（至少留 10px）
	var board_bottom := board_pos.y + 8 * 104
	var hand_top := hand_pos.y - 104
	_expect(board_bottom + 10 <= hand_top, "board bottom clears the hand top")

	var board := BoardScene.instantiate() as Board
	_expect(board.cell_size == LayoutConfigScript.CELL_SIZE, "board defaults to the configured cell size")
	board.free()

	var hand := HandAreaScript.new()
	_expect(hand.card_width == LayoutConfigScript.CARD_W, "hand card slot width derives from config")
	_expect(hand.card_spacing == LayoutConfigScript.HAND_SPACING, "hand card spacing derives from config")

	call_deferred("_run_deferred_tests")

func _run_deferred_tests() -> void:
	_test_board_drop_detector()
	_test_card_entity_sizing()
	_test_card_view_label_container()
	_test_game_manager_centering()
	await _test_game_manager_subviewport_reflow()
	_finish_tests()

func _test_board_drop_detector() -> void:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	var shape_node := board.get_node_or_null("DropDetector/CollisionShape2D") as CollisionShape2D
	var shape := shape_node.shape as RectangleShape2D
	_expect(shape != null and shape.size == Vector2(1040, 832), "drop detector matches the resized grid")
	_expect(shape_node.position == Vector2(520, 416), "drop detector centers on the resized grid")
	board.queue_free()

func _test_card_entity_sizing() -> void:
	var card := CardEntityScene.instantiate() as CardEntity
	root.add_child(card)
	var shape := (card.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	_expect(shape != null and shape.size == Vector2(104, 208), "card collision box covers two resized cells")
	var card_view := card.get_node("CardView") as Control
	_expect(card_view.size == Vector2(84, 188), "card view derives from the configured cell size")
	card.queue_free()

func _test_card_view_label_container() -> void:
	var view := CardViewScene.instantiate() as Control
	root.add_child(view)
	view.size = Vector2(84, 188)
	var label := view.get_node("LabelContainer") as Control
	_expect(label.offset_bottom == 188.0, "label container pins to the resized card bottom")
	_expect(label.offset_top == 165.0, "label container bar height stays 23")
	view.queue_free()

func _test_game_manager_centering() -> void:
	var gm := GameManagerScene.instantiate()
	_expect(gm.configure_run(RevivalDeck), "layout setup configures a starting deck")
	root.add_child(gm)
	var gameplay_canvas := gm.get_node_or_null("GameplayCanvas")
	var pilgrim_crest_hud := gm.get_node_or_null("GameplayCanvas/PilgrimCrestHud") as PilgrimCrestHud
	var hand_tray := gm.get_node_or_null("GameplayCanvas/HandTray") as HandTray
	_expect(pilgrim_crest_hud != null, "game manager owns a Pilgrim Crest HUD inside the gameplay canvas")
	_expect(pilgrim_crest_hud != null and pilgrim_crest_hud.get_parent() == gameplay_canvas, "Pilgrim Crest HUD scales with the gameplay canvas")
	_expect(pilgrim_crest_hud != null and pilgrim_crest_hud.z_index == RenderPriority.PLAYER_HUD, "Pilgrim Crest HUD uses the player HUD render layer")
	_expect(pilgrim_crest_hud != null and pilgrim_crest_hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Pilgrim Crest HUD does not block card input")
	_expect(hand_tray != null, "game manager owns a hand tray inside the gameplay canvas")
	_expect(hand_tray != null and hand_tray.get_parent() == gameplay_canvas, "hand tray scales with the gameplay canvas")
	_expect(hand_tray != null and hand_tray.z_index == -1, "hand tray uses the required render layer")
	var hand_tray_index := gameplay_canvas.get_children().find(hand_tray) if gameplay_canvas != null else -1
	var hand_manager_index := gameplay_canvas.get_children().find(gm.hand_area) if gameplay_canvas != null else -1
	_expect(hand_tray_index >= 0 and hand_manager_index == hand_tray_index + 1, "hand tray is immediately before hand manager in the gameplay canvas")
	_expect(hand_tray != null and hand_tray.mouse_filter == Control.MOUSE_FILTER_IGNORE, "hand tray does not block card input")
	var hand_count := hand_tray.get_node_or_null("HandCount") as Label if hand_tray != null else null
	_expect(
		hand_count != null and hand_count.text == "HAND · %d / %d" % [gm.hand_area.get_card_count(), gm.hand_area.max_hand_size],
		"game manager syncs the initial hand count to the tray"
	)
	_expect(
		gm.hand_area.hand_count_changed.is_connected(gm._sync_hand_tray),
		"game manager connects hand count changes to the hand tray"
	)
	var hand_tray_connection_count := 0
	for connection in gm.hand_area.hand_count_changed.get_connections():
		if connection.get("callable") == gm._sync_hand_tray:
			hand_tray_connection_count += 1
	_expect(hand_tray_connection_count == 1, "game manager connects the hand tray exactly once")
	gm.hand_area.hand_count_changed.emit(2, gm.hand_area.max_hand_size)
	_expect(
		hand_count != null and hand_count.text == "HAND · 2 / %d" % gm.hand_area.max_hand_size,
		"game manager syncs post-initialization hand count changes to the tray"
	)
	_expect(gameplay_canvas is GameplayCanvasScript, "game manager owns a GameplayCanvas")
	_expect(gm.board.get_parent() == gameplay_canvas, "board is inside gameplay canvas")
	_expect(gm.hand_area.get_parent() == gameplay_canvas, "hand is inside gameplay canvas")
	_expect(gm.card_manager.get_parent() == gameplay_canvas, "card manager is inside gameplay canvas")
	_expect(gm.drag_layer.get_parent() == gameplay_canvas, "drag layer is inside gameplay canvas")
	_expect(gm.get_node_or_null("EventModalLayer") is CanvasLayer, "event modal layer remains a screen UI layer")

	var design := LayoutConfigScript.DESIGN_VIEWPORT_SIZE
	var expected_board := LayoutConfigScript.board_origin(
		design, gm.board.width, gm.board.height, gm.board.cell_size
	)
	var expected_hand := LayoutConfigScript.hand_origin(design)
	_expect(gm.board.position == expected_board, "board uses fixed design coordinates")
	_expect(gm.hand_area.position == expected_hand, "hand uses fixed design coordinates")

	if gameplay_canvas is GameplayCanvasScript:
		var view := gm.get_viewport().get_visible_rect().size
		_expect(
			gameplay_canvas.position == (view - design * gameplay_canvas.scale.x) * 0.5,
			"canvas is centered in the actual viewport"
		)
		_expect(gameplay_canvas.scale.x == gameplay_canvas.scale.y, "canvas scale remains uniform")
	_expect(
		gm.get_viewport().size_changed.is_connected(gm._center_layout),
		"game manager reflows when the viewport changes"
	)
	gm.queue_free()

func _test_game_manager_subviewport_reflow() -> void:
	var game_viewport := SubViewport.new()
	game_viewport.size = Vector2i(1280, 800)
	root.add_child(game_viewport)

	var gm := GameManagerScene.instantiate()
	_expect(gm.configure_run(RevivalDeck), "subviewport layout setup configures a starting deck")
	game_viewport.add_child(gm)
	if not gm.is_node_ready():
		await gm.ready

	_expect(gm.is_node_ready(), "game manager is ready inside the subviewport")
	var design := LayoutConfigScript.DESIGN_VIEWPORT_SIZE
	var expected_board := LayoutConfigScript.board_origin(
		design, gm.board.width, gm.board.height, gm.board.cell_size
	)
	var expected_hand := LayoutConfigScript.hand_origin(design)
	var gameplay_canvas := gm.get_node_or_null("GameplayCanvas") as GameplayCanvas
	_expect(gameplay_canvas != null, "subviewport game manager owns a gameplay canvas")
	if gameplay_canvas != null:
		_expect(gm.board.position == expected_board, "board keeps design coordinates at 1280x800")
		_expect(gm.hand_area.position == expected_hand, "hand keeps design coordinates at 1280x800")
		_expect(is_equal_approx(gameplay_canvas.scale.x, 2.0 / 3.0), "canvas scale is 2/3 at 1280x800")
		_expect(gameplay_canvas.scale.x == gameplay_canvas.scale.y, "canvas scale is uniform at 1280x800")
		_expect(
			gameplay_canvas.position.distance_to(Vector2(0, 40)) < 0.001,
			"canvas is centered at 1280x800"
		)

	var resize_waiter := ViewportSizeChangedWaiter.new()
	resize_waiter.bind(game_viewport)
	game_viewport.size = Vector2i(1920, 1080)
	await resize_waiter.wait()

	if gameplay_canvas != null:
		_expect(gm.board.position == expected_board, "board keeps design coordinates after subviewport resize")
		_expect(gm.hand_area.position == expected_hand, "hand keeps design coordinates after subviewport resize")
		_expect(is_equal_approx(gameplay_canvas.scale.x, 1.0), "canvas scale updates to 1.0 after resize")
		_expect(gameplay_canvas.scale.x == gameplay_canvas.scale.y, "canvas scale remains uniform after resize")
		_expect(
			gameplay_canvas.position.distance_to(Vector2.ZERO) < 0.001,
			"canvas is centered after subviewport resize"
		)

	game_viewport.free()

func _finish_tests() -> void:
	quit(1 if _failure_count > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)