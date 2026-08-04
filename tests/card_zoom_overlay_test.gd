extends SceneTree

const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var host := Node2D.new()
	root.add_child(host)
	current_scene = host

	var card := CardEntityScene.instantiate() as CardEntity
	host.add_child(card)
	await process_frame
	card._show_zoom()
	await process_frame

	var background := host.get_node_or_null("CardZoomOverlay/ZoomBg") as ColorRect
	var zoom_view := host.get_node_or_null("CardZoomOverlay/ZoomBg/ZoomView") as PanelContainer
	_expect(background != null, "opening a card creates a zoom background")
	if background != null:
		_expect(background.anchors_preset == Control.PRESET_FULL_RECT, "zoom background uses full-rect anchors")
		_expect(background.anchor_right == 1.0 and background.anchor_bottom == 1.0, "zoom background reaches the viewport edges")
		_expect(background.offset_left == 0.0 and background.offset_top == 0.0, "zoom background has no inset at the top-left")
		_expect(background.offset_right == 0.0 and background.offset_bottom == 0.0, "zoom background has no inset at the bottom-right")

	if background != null and zoom_view != null:
		var background_center := background.get_global_rect().get_center()
		var record_center := zoom_view.get_global_rect().get_center()
		_expect(record_center.distance_to(background_center) <= 1.0, "record is centered in the zoom background; got %s instead of %s" % [record_center, background_center])

	var preview := zoom_view.get_node_or_null("SheetMargin/Sheet/ContentRow/CardPreviewHost/CardPreview") if zoom_view != null else null
	var detail := zoom_view.get_node_or_null("SheetMargin/Sheet/ContentRow/DetailColumn") if zoom_view != null else null
	var hint := zoom_view.get_node_or_null("SheetMargin/Sheet/CloseHint") as Label if zoom_view != null else null
	_expect(zoom_view != null and zoom_view.mouse_filter == Control.MOUSE_FILTER_STOP, "record blocks clicks inside its sheet")
	_expect(preview != null and preview.get("card_inst") == card.card_instance, "record preview uses the opened CardInstance")
	_expect(preview != null and preview is Control and preview.mouse_filter == Control.MOUSE_FILTER_IGNORE, "record preview is display-only")
	_expect(detail != null, "record includes a detail column")
	_expect(hint != null and hint.text == "CLICK OUTSIDE OR PRESS ESC TO CLOSE", "record uses the approved English close hint")

	var stats := detail.get_node_or_null("Stats") as HBoxContainer if detail != null else null
	var stat_count := stats.get_child_count() if stats != null else 0
	if zoom_view != null:
		zoom_view.refresh_display()
	_expect(preview != null and preview.get_parent().get_child_count() == 1, "record refresh reuses its card preview")
	_expect(stats != null and stats.get_child_count() == stat_count, "record refresh replaces stat seals")

	if background != null and zoom_view != null:
		var inside_click := InputEventMouseButton.new()
		inside_click.button_index = MOUSE_BUTTON_LEFT
		inside_click.pressed = true
		inside_click.position = zoom_view.get_global_rect().get_center()
		card._on_zoom_bg_input(inside_click, background)
		await process_frame
		_expect(card._zoom_overlay != null, "clicking inside the record keeps it open")

	card._hide_zoom()
	await process_frame
	card._show_zoom()
	await process_frame
	background = host.get_node_or_null("CardZoomOverlay/ZoomBg") as ColorRect
	if background != null:
		var outside_click := InputEventMouseButton.new()
		outside_click.button_index = MOUSE_BUTTON_LEFT
		outside_click.pressed = true
		outside_click.position = background.get_global_rect().end - Vector2(4, 4)
		card._on_zoom_bg_input(outside_click, background)
		await process_frame
		_expect(card._zoom_overlay == null, "clicking outside the record closes it")

	card._show_zoom()
	await process_frame
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	card._input(cancel)
	await process_frame
	_expect(card._zoom_overlay == null, "pressing Esc closes the record")

	host.free()
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)