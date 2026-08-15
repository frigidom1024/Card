extends SceneTree

const LayoutConfigScript = preload("res://scripts/game/layout_config.gd")
const GameplayCanvasScript = preload("res://scripts/game/gameplay_canvas.gd")
const HandAreaScript = preload("res://scripts/game/hand.gd")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


class ViewportSizeChangedWaiter:
	extends RefCounted
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
	_expect(
		LayoutConfigScript.DESIGN_VIEWPORT_SIZE == Vector2(1920, 1080),
		"layout uses the 1920x1080 design viewport"
	)
	_expect(LayoutConfigScript.CELL_SIZE == 104, "CELL_SIZE is 104 at the 1920x1080 baseline")
	_expect(LayoutConfigScript.CARD_MARGIN == 20, "CARD_MARGIN preserves the configured card inset")
	_expect(LayoutConfigScript.CARD_W == 84, "CARD_W derives from CELL_SIZE minus margin")
	_expect(LayoutConfigScript.CARD_H == 154, "CARD_H matches the redesigned card face height")
	_expect(LayoutConfigScript.HAND_SPACING == 36, "HAND_SPACING derives from CELL_SIZE")
	_expect(LayoutConfigScript.HAND_STEP == 120, "HAND_STEP is card width plus spacing")
	_expect(
		LayoutConfigScript.card_view_rect(104).size == Vector2(84, 154),
		"card face rectangle matches the redesigned visual card size"
	)

	var card_rect := LayoutConfigScript.card_view_rect(104)
	_expect(card_rect.size == Vector2(84, 154), "card view rect matches the redesigned card size")
	_expect(card_rect.position == Vector2(-40, -81), "card view rect matches the CardEntity scene placement")

	var board_pos := LayoutConfigScript.board_origin(Vector2(1920, 1080), 10, 8, 104)
	_expect(board_pos == Vector2(440, 19), "board origin centers the 1040x832 grid horizontally")

	var hand_pos := LayoutConfigScript.hand_origin(Vector2(1920, 1080))
	_expect(hand_pos == Vector2(960, 965), "hand origin centers and hugs the bottom")

	# 棋盘底与手牌顶不重叠（至少留 10px）
	var board_bottom := board_pos.y + 8 * 104
	var hand_top := hand_pos.y - 104
	_expect(board_bottom + 10 <= hand_top, "board bottom clears the hand top")

	var hand := HandAreaScript.new()
	_expect(
		hand.card_width == LayoutConfigScript.CARD_W, "hand card slot width derives from config"
	)
	_expect(
		hand.card_spacing == LayoutConfigScript.HAND_SPACING,
		"hand card spacing derives from config"
	)

	call_deferred("_run_deferred_tests")


func _run_deferred_tests() -> void:
	_test_card_entity_sizing()
	_test_game_manager_centering()
	await _test_game_manager_subviewport_reflow()
	_finish_tests()


func _test_card_entity_sizing() -> void:
	var card := CardEntityScene.instantiate() as CardEntity
	root.add_child(card)
	var shape := (card.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	_expect(
		shape != null and shape.size == Vector2(104, 208),
		"card collision box covers two resized cells"
	)
	var card_view := card.get_node("CardView") as Control
	_expect(card_view.size == Vector2(84, 154), "card view uses the redesigned card dimensions")
	card.queue_free()


func _test_game_manager_centering() -> void:
	var gm := GameManagerScene.instantiate()
	_expect(gm.configure_run(RevivalDeck), "layout setup configures a starting deck")
	root.add_child(gm)
	var gameplay_canvas := gm.get_node_or_null("GameplayCanvas")
	var hud := gm.get_node_or_null("GameplayCanvas/Hud") as Control
	var game_info := gm.get_node_or_null("GameplayCanvas/Hud/GameInfo") as GameInfo
	_expect(game_info != null, "game manager owns GameInfo inside HUD")
	_expect(
		game_info != null and game_info.get_parent() == hud,
		"GameInfo follows the HUD layout"
	)
	_expect(
		game_info != null and game_info.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"GameInfo does not block card input"
	)
	var manager_source := FileAccess.get_file_as_string("res://scripts/game_manager.gd")
	_expect(
		manager_source.contains("gameplay_canvas.fit_to_viewport"),
		"GameManager delegates viewport fitting to GameplayCanvas"
	)
	_expect(
		not manager_source.contains("size_changed.connect(_center_layout)"),
		"GameManager does not auto-reflow layout on viewport resize"
	)
	_expect(gameplay_canvas is GameplayCanvasScript, "game manager owns a GameplayCanvas")
	_expect(gm.board.get_parent() == hud, "board is inside HUD")
	_expect(gm.hand_zone.get_parent() == hud, "hand zone is inside HUD")
	_expect(gm.drag_layer.get_parent() == gameplay_canvas, "drag layer is inside gameplay canvas")
	_expect(
		gm.get_node_or_null("EventModalLayer") is CanvasLayer,
		"event modal layer remains a screen UI layer"
	)

	_expect(gameplay_canvas is GameplayCanvasScript, "game manager owns a GameplayCanvas")

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
	var manager_source := FileAccess.get_file_as_string("res://scripts/game_manager.gd")
	_expect(
		not manager_source.contains("size_changed.connect(_center_layout)"),
		"subviewport resize does not route through GameManager layout code"
	)

	game_viewport.free()


func _finish_tests() -> void:
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
