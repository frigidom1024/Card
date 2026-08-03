extends SceneTree

const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const CardInfoOverlayScene = preload("res://scenes/card_view/card_info_overlay.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_display_only_card_ignores_gameplay_interactions()
	await _test_display_mode_can_be_set_before_entering_tree()
	await _test_default_card_remains_interactable()
	quit(1 if _failure_count > 0 else 0)


func _test_display_only_card_ignores_gameplay_interactions() -> void:
	var overlay := CardInfoOverlayScene.instantiate() as CardInfoOverlay
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(CardInstance.new(RevivalDeck.get_root_card()))
	card.card_info_overlay = overlay
	root.add_child(overlay)
	root.add_child(card)
	await process_frame

	card._on_mouse_entered()
	await process_frame
	await process_frame
	var panel := overlay.get_node_or_null("CardInfo") as PanelContainer
	_expect(panel != null and panel.visible, "interactive card can show shared hover details")

	card.set_display_only(true)
	_expect(card.is_display_only(), "card records display-only mode")
	_expect(not card.input_pickable, "display-only card disables Area2D input")
	_expect(card.state == CardEntity.State.NORMAL, "display-only card has normal interaction state")
	_expect(panel != null and not panel.visible, "display-only mode clears its shared hover details")

	card._on_mouse_entered()
	_expect(card.state == CardEntity.State.NORMAL, "display-only card ignores hover")

	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	card._on_input_event(root, left_click, 0)
	_expect(not card._dragging, "display-only card cannot start dragging")

	card._show_zoom()
	_expect(card._zoom_overlay == null, "display-only card cannot open zoom overlay")
	card.free()
	overlay.free()
	await process_frame


func _test_display_mode_can_be_set_before_entering_tree() -> void:
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(CardInstance.new(RevivalDeck.get_root_card()))
	card.set_display_only(true)
	_expect(card.is_display_only(), "card can be made display-only before it enters the scene tree")
	_expect(not card.input_pickable, "preconfigured display-only card disables Area2D input")

	root.add_child(card)
	await process_frame
	_expect(not card.input_pickable, "display-only input state persists after ready")
	card.free()
	await process_frame


func _test_default_card_remains_interactable() -> void:
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(CardInstance.new(RevivalDeck.get_root_card()))
	root.add_child(card)
	await process_frame

	_expect(not card.is_display_only(), "gameplay card starts in interactive mode")
	_expect(card.input_pickable, "gameplay card keeps Area2D input enabled")
	card._on_mouse_entered()
	_expect(card.state == CardEntity.State.HOVER, "gameplay card still responds to hover")
	card.free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
