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
	_expect(background != null, "opening a card creates a zoom background")
	if background != null:
		_expect(background.anchors_preset == Control.PRESET_FULL_RECT, "zoom background uses full-rect anchors")
		_expect(background.anchor_right == 1.0 and background.anchor_bottom == 1.0, "zoom background reaches the viewport edges")
		_expect(background.offset_left == 0.0 and background.offset_top == 0.0, "zoom background has no inset at the top-left")
		_expect(background.offset_right == 0.0 and background.offset_bottom == 0.0, "zoom background has no inset at the bottom-right")

	card._hide_zoom()
	await process_frame
	host.free()
	quit(1 if _failure_count > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
