extends SceneTree

const CardInfoOverlayScene = preload("res://scenes/card_view/card_info_overlay.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_right_side_and_left_flip()
	_test_vertical_position_is_clamped()
	await _test_hover_panel_stays_upright_and_hides_on_exit()
	_test_game_manager_keeps_overlay_outside_gameplay_canvas()
	quit(1 if _failure_count > 0 else 0)


func _test_right_side_and_left_flip() -> void:
	var overlay := CardInfoOverlayScene.instantiate() as CardInfoOverlay
	var panel_size := Vector2(220.0, 140.0)
	var viewport_size := Vector2(1280.0, 720.0)

	var right_position := overlay.calculate_panel_position(
		Rect2(Vector2(320.0, 200.0), Vector2(84.0, 150.0)), panel_size, viewport_size
	)
	_expect(right_position.x > 404.0, "panel prefers the card's right side")

	var left_position := overlay.calculate_panel_position(
		Rect2(Vector2(1180.0, 200.0), Vector2(84.0, 150.0)), panel_size, viewport_size
	)
	_expect(left_position.x + panel_size.x < 1180.0, "panel flips left near the viewport edge")
	overlay.free()


func _test_vertical_position_is_clamped() -> void:
	var overlay := CardInfoOverlayScene.instantiate() as CardInfoOverlay
	var panel_size := Vector2(220.0, 140.0)
	var viewport_size := Vector2(1280.0, 720.0)

	var top_position := overlay.calculate_panel_position(
		Rect2(Vector2(320.0, -40.0), Vector2(84.0, 150.0)), panel_size, viewport_size
	)
	_expect(top_position.y >= CardInfoOverlay.VIEWPORT_MARGIN, "panel stays inside the top viewport margin")

	var bottom_position := overlay.calculate_panel_position(
		Rect2(Vector2(320.0, 680.0), Vector2(84.0, 150.0)), panel_size, viewport_size
	)
	_expect(
		bottom_position.y + panel_size.y <= viewport_size.y - CardInfoOverlay.VIEWPORT_MARGIN,
		"panel stays inside the bottom viewport margin"
	)
	overlay.free()


func _test_hover_panel_stays_upright_and_hides_on_exit() -> void:
	var overlay := CardInfoOverlayScene.instantiate() as CardInfoOverlay
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(CardInstance.new(RevivalDeck.get_root_card()))
	card.position = Vector2(300.0, 240.0)
	card.rotation_degrees = 90.0
	card.card_info_overlay = overlay
	root.add_child(overlay)
	root.add_child(card)
	await process_frame

	card._on_mouse_entered()
	await process_frame
	await process_frame

	var panel := overlay.get_node_or_null("CardInfo") as PanelContainer
	_expect(panel != null and panel.visible, "hover shows the shared card info panel")
	_expect(
		panel != null and panel.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"panel does not block card exit"
	)
	_expect(
		panel != null and is_zero_approx(panel.get_global_transform_with_canvas().get_rotation()),
		"info panel remains upright when its card rotates"
	)

	card._on_mouse_exited()
	_expect(panel != null and not panel.visible, "panel hides immediately when the pointer leaves the card")

	card.free()
	overlay.free()
	await process_frame


func _test_game_manager_keeps_overlay_outside_gameplay_canvas() -> void:
	var manager := GameManagerScene.instantiate()
	var gameplay_canvas := manager.get_node_or_null("GameplayCanvas")
	var overlay := manager.get_node_or_null("CardInfoOverlay") as CanvasLayer
	var modal_layer := manager.get_node_or_null("EventModalLayer") as CanvasLayer
	_expect(
		overlay != null and gameplay_canvas != null and not gameplay_canvas.is_ancestor_of(overlay),
		"card info overlay is independent from gameplay scaling"
	)
	_expect(
		overlay != null and modal_layer != null and overlay.layer < modal_layer.layer,
		"event modals remain above card info"
	)
	manager.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)