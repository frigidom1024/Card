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
	await _test_card_entity_owns_hover_overlay()
	await _test_hover_panel_stays_upright_and_hides_on_exit()
	await _test_field_note_content_and_pass_through()
	_test_game_manager_does_not_own_shared_overlay()
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


func _test_card_entity_owns_hover_overlay() -> void:
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(CardInstance.new(RevivalDeck.get_root_card()))
	root.add_child(card)
	await process_frame

	card._on_mouse_entered()
	await process_frame
	await process_frame

	var overlay := card.get_node_or_null("CardInfoOverlay") as CardInfoOverlay
	var panel := overlay.get_node_or_null("CardInfo") as PanelContainer if overlay != null else null
	_expect(overlay != null, "standalone card entity creates its own hover overlay")
	_expect(panel != null and panel.visible, "standalone card hover displays its own info panel")
	_expect(
		overlay != null and overlay.layer < RenderPriority.EVENT_MODAL,
		"card-owned info panel remains below event modals"
	)

	card.free()
	await process_frame

func _test_hover_panel_stays_upright_and_hides_on_exit() -> void:
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(CardInstance.new(RevivalDeck.get_root_card()))
	card.position = Vector2(300.0, 240.0)
	card.rotation_degrees = 90.0
	root.add_child(card)
	await process_frame

	card._on_mouse_entered()
	await process_frame
	await process_frame

	var overlay := card.get_node_or_null("CardInfoOverlay") as CardInfoOverlay
	var panel := overlay.get_node_or_null("CardInfo") as PanelContainer if overlay != null else null
	_expect(panel != null and panel.visible, "hover shows the card-owned info panel")
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
	await process_frame



func _test_field_note_content_and_pass_through() -> void:
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(CardInstance.create_debug_card())
	root.add_child(card)
	await process_frame

	card._on_mouse_entered()
	await process_frame
	await process_frame

	var overlay := card.get_node_or_null("CardInfoOverlay") as CardInfoOverlay
	var panel := overlay.get_node_or_null("CardInfo") as PanelContainer if overlay != null else null
	var meta := panel.get_node_or_null("MarginContainer/Content/MetaLabel") as Label if panel != null else null
	var title := panel.get_node_or_null("MarginContainer/Content/TitleLabel") as Label if panel != null else null
	var stats := panel.get_node_or_null("MarginContainer/Content/Stats") as HBoxContainer if panel != null else null
	var description := panel.get_node_or_null("MarginContainer/Content/DescriptionLabel") as Label if panel != null else null
	var tags := panel.get_node_or_null("MarginContainer/Content/Tags") as FlowContainer if panel != null else null

	_expect(meta != null and meta.text.contains("EPIC") and meta.text.contains("CARD"), "field note shows English rarity and type")
	_expect(title != null and title.text == "All Things Revival", "field note shows the card name")
	_expect(stats != null and stats.get_child_count() > 0, "field note shows non-zero stat seals")
	_expect(description != null and description.autowrap_mode != TextServer.AUTOWRAP_OFF, "field note wraps its summary")
	_expect(tags != null and tags.get_child_count() > 0, "field note shows English tags")
	_expect(panel != null and panel.size.x >= 280.0, "field note uses a readable minimum width")
	_expect(stats != null and stats.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE, "stat seals ignore pointer input")
	_expect(tags != null and tags.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE, "tags ignore pointer input")

	var stat_count := stats.get_child_count() if stats != null else 0
	var tag_count := tags.get_child_count() if tags != null else 0
	if panel != null:
		panel.refresh_display()
	_expect(stats != null and stats.get_child_count() == stat_count, "field note refresh replaces stat seals")
	_expect(tags != null and tags.get_child_count() == tag_count, "field note refresh replaces tag labels")

	card.free()
	await process_frame

func _test_game_manager_does_not_own_shared_overlay() -> void:
	var manager := GameManagerScene.instantiate()
	var overlay := manager.get_node_or_null("CardInfoOverlay") as CanvasLayer
	var modal_layer := manager.get_node_or_null("EventModalLayer") as CanvasLayer
	_expect(overlay == null, "game manager does not own a shared card info overlay")
	_expect(modal_layer != null, "game manager keeps an event modal layer")
	manager.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)