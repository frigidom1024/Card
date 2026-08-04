extends SceneTree

const RootSelectionScene = preload("res://scenes/home/root_selection_screen.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var screen := RootSelectionScene.instantiate() as RootSelectionScreen
	screen.configure([RevivalDeck])
	root.add_child(screen)
	current_scene = screen
	await process_frame
	await process_frame

	var preview_panel := screen.get_node_or_null("SafeArea/Content/ContentLayout/MainArea/PreviewPanel") as PanelContainer
	var preview_layout := screen.get_node_or_null("SafeArea/Content/ContentLayout/MainArea/PreviewPanel/PreviewLayout") as VBoxContainer
	var root_slot := screen.get_node_or_null("SafeArea/Content/ContentLayout/MainArea/PreviewPanel/PreviewLayout/RootPreviewSlot") as Control
	var root_preview := root_slot.get_child(0) as CardEntity if root_slot != null and root_slot.get_child_count() == 1 else null
	var card_view := root_preview.get_node_or_null("CardView") as Control if root_preview != null else null
	_expect(preview_panel != null and preview_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "root preview panel passes pointer input to its card previews")
	_expect(preview_layout != null and preview_layout.mouse_filter == Control.MOUSE_FILTER_IGNORE, "root preview layout passes pointer input to its card previews")
	_expect(root_preview != null and root_preview.is_display_only(), "root preview remains a display-only CardEntity")
	_expect(root_preview != null and root_preview.input_pickable, "root preview accepts pointer hover while display-only")
	_expect(card_view != null and card_view.mouse_filter == Control.MOUSE_FILTER_STOP, "root preview card face receives UI pointer events")

	if root_preview != null and card_view != null:
		card_view.emit_signal("mouse_entered")
		await process_frame
		await process_frame

		var overlay := root_preview.get_node_or_null("CardInfoOverlay") as CardInfoOverlay
		var info_panel := overlay.get_node_or_null("CardInfo") as PanelContainer if overlay != null else null
		_expect(info_panel != null and info_panel.visible, "hovering a root preview opens its card information")
		_expect(root_preview.state == CardEntity.State.NORMAL, "root preview hover does not enter gameplay interaction state")

		var right_click := InputEventMouseButton.new()
		right_click.button_index = MOUSE_BUTTON_RIGHT
		right_click.pressed = true
		card_view.emit_signal("gui_input", right_click)
		await process_frame
		_expect(root_preview._zoom_overlay != null, "right-clicking a root preview opens the zoom record")
		root_preview._hide_zoom()

		card_view.emit_signal("mouse_exited")
		await process_frame
		_expect(info_panel != null and not info_panel.visible, "leaving a root preview hides its card information")

	screen.free()
	await process_frame
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)