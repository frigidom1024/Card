extends SceneTree

const RootSelectionScene = preload("res://scenes/home/root_selection_screen.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var screen := RootSelectionScene.instantiate() as RootSelectionScreen
	screen.configure([RevivalDeck])
	root.size = Vector2i(1920, 1080)
	root.add_child(screen)
	current_scene = screen
	await process_frame
	await process_frame
	await process_frame

	var root_slot := screen.find_child("RootPreviewSlot", true, false) as Control
	var starter_row := screen.find_child("RemainingStarterCardPreviewRow", true, false) as Control
	var hover_layer := screen.get_node_or_null("HoverInfoLayer") as Control
	var hover_info := screen.get_node_or_null("HoverInfoLayer/HoverInfo") as Control
	var root_preview := root_slot.get_child(0) as Card if root_slot != null and root_slot.get_child_count() == 1 else null

	_expect(root_preview != null, "selected root is rendered with the new Card scene")
	_expect(
		root_preview != null
			and root_preview.get_card_inst() != null
			and root_preview.get_card_inst().card_data == RevivalDeck.get_root_card(),
		"central Card is bound to the selected deck root",
	)
	_expect(root_preview != null and not root_preview.draggable, "central root preview cannot be dragged")
	_expect(
		root_preview != null and root_preview.scale.x >= 1.95,
		"central root card is visibly larger than the previous deck preview",
	)
	_expect(
		starter_row != null
			and starter_row.get_child_count() == RevivalDeck.get_remaining_starter_cards().size(),
		"bottom row renders every non-root card in the selected starting deck",
	)
	if starter_row != null:
		for index in starter_row.get_child_count():
			var preview := starter_row.get_child(index) as Card
			var expected_card := RevivalDeck.get_remaining_starter_cards()[index]
			_expect(
				preview != null
					and preview.get_card_inst() != null
					and preview.get_card_inst().card_data == expected_card,
				"bottom preview %d uses the new Card model and preserves deck order" % index,
			)
			_expect(preview != null and not preview.draggable, "bottom preview %d cannot be dragged" % index)
			_expect(
				preview != null and preview.scale.x >= 1.0,
				"bottom preview %d remains clearly readable at reference scale" % index,
			)


	var starter_layout := _capture_preview_layout(starter_row)
	var has_vertical_variation := false
	var has_rotation := false
	var horizontal_step_total := 0.0
	if starter_layout.size() > 1:
		var first_y: float = starter_layout[0].y
		for index in starter_layout.size():
			var transform := starter_layout[index]
			has_vertical_variation = has_vertical_variation or not is_equal_approx(transform.y, first_y)
			has_rotation = has_rotation or absf(transform.z) >= 0.5
			_expect(absf(transform.z) <= 5.0, "bottom preview rotation stays within the subtle five-degree range")
			if index > 0:
				horizontal_step_total += absf(transform.x - starter_layout[index - 1].x)
		var average_horizontal_step := horizontal_step_total / float(starter_layout.size() - 1)
		_expect(
			average_horizontal_step >= 110.0 and average_horizontal_step <= 130.0,
			"bottom previews use a compact horizontal spacing near 122 pixels",
		)
	_expect(has_vertical_variation, "bottom previews use slightly varied vertical positions")
	_expect(has_rotation, "bottom previews use slightly varied resting angles")

	_expect(
		hover_layer != null
			and hover_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and hover_layer.z_index >= 1000,
		"root selection owns a non-interactive top-level HoverInfo layer",
	)
	_expect(
		hover_info != null and hover_info.is_in_group("card_hover_info") and not hover_info.visible,
		"root selection exposes the existing shared HoverInfo to its cards",
	)

	if root_preview != null and hover_info != null:
		var preview_scale_before_hover := root_preview.scale
		root_preview.emit_signal("mouse_entered")
		await process_frame
		await process_frame
		if root_preview.tween_hover != null:
			root_preview.tween_hover.custom_step(1.0)
		_expect(hover_info.visible, "hovering the central root opens HoverInfo")
		_expect(hover_info.get("card_inst") == root_preview.get_card_inst(), "HoverInfo receives the hovered root instance")
		_expect(
			root_preview.scale.is_equal_approx(preview_scale_before_hover * 1.2),
			"hover emphasis scales relative to the preview's configured size",
		)

		root_preview.call("_start_drag", root_preview.size * 0.5)
		_expect(not root_preview.dragging, "a non-draggable preview ignores drag start")
		_expect(hover_info.visible, "ignored drag attempts do not hide HoverInfo")

		root_preview.emit_signal("mouse_exited")
		await process_frame
		if root_preview.tween_hover != null:
			root_preview.tween_hover.custom_step(1.0)
		_expect(not hover_info.visible, "leaving the central root hides HoverInfo")
		_expect(
			root_preview.scale.is_equal_approx(preview_scale_before_hover),
			"leaving hover restores the preview's configured size",
		)

	screen.configure([RevivalDeck])
	await process_frame
	await process_frame
	await process_frame
	var refreshed_starter_row := screen.find_child("RemainingStarterCardPreviewRow", true, false) as Control
	_expect(
		_preview_layouts_match(starter_layout, _capture_preview_layout(refreshed_starter_row)),
		"bottom preview scatter remains stable when the same deck is rebuilt",
	)

	screen.free()
	await process_frame
	quit(1 if _failure_count > 0 else 0)


func _capture_preview_layout(container: Control) -> Array[Vector3]:
	var layout: Array[Vector3] = []
	if container == null:
		return layout
	for child in container.get_children():
		var card := child as Card
		if card != null:
			layout.append(Vector3(card.position.x, card.position.y, card.rotation_degrees))
	return layout


func _preview_layouts_match(first: Array[Vector3], second: Array[Vector3]) -> bool:
	if first.size() != second.size():
		return false
	for index in first.size():
		if not first[index].is_equal_approx(second[index]):
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
