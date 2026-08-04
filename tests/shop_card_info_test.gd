extends SceneTree

const ShopScene = preload("res://scenes/game/event_shop.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var shop := ShopScene.instantiate() as ShopEventView
	_expect(shop != null, "shop scene instantiates as ShopEventView")
	if shop == null:
		_finish_tests()
		return

	root.add_child(shop)
	current_scene = shop
	await process_frame
	await process_frame

	var artwork := shop.get_node_or_null("CenterContainer/Panel/Content/MainContent/ShopArtworkFrame/ShopArtwork") as TextureRect
	_expect(artwork != null, "shop exposes an inspector-editable artwork slot")
	_expect(artwork == null or artwork.mouse_filter == Control.MOUSE_FILTER_IGNORE, "shop artwork never blocks offer input")

	var preview := shop.get_node_or_null("CenterContainer/Panel/Content/MainContent/OfferArea/OfferContainer/OfferSlot1/Content/CardPreviewHolder/CardPreview") as CardEntity
	_expect(preview != null, "shop offer uses CardEntity for shared card interactions")
	if preview != null:
		_expect(preview.is_display_only(), "shop card preview remains display-only")
		_expect(preview.input_pickable, "shop card preview accepts hover and right-click input")
		var card_view := preview.get_node_or_null("CardView") as Control
		_expect(card_view != null and card_view.mouse_filter == Control.MOUSE_FILTER_STOP, "shop card face receives UI pointer events")
		if card_view != null:
			card_view.emit_signal("mouse_entered")
			await process_frame
			await process_frame
			var overlay := preview.get_node_or_null("CardInfoOverlay") as CardInfoOverlay
			var info_panel := overlay.get_node_or_null("CardInfo") as PanelContainer if overlay != null else null
			_expect(info_panel != null and info_panel.visible, "hovering a shop card opens card information")

			var right_click := InputEventMouseButton.new()
			right_click.button_index = MOUSE_BUTTON_RIGHT
			right_click.pressed = true
			card_view.emit_signal("gui_input", right_click)
			await process_frame
			_expect(preview._zoom_overlay != null, "right-clicking a shop card opens the zoom overlay")
			preview._hide_zoom()

	shop.free()
	await process_frame
	_finish_tests()


func _finish_tests() -> void:
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
