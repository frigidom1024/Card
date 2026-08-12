class_name CardInfoController
extends Node

## Owns the non-gameplay information surfaces: hover note and zoom overlay.
## CardEntity keeps compatibility wrappers, but this controller owns creation,
## positioning, closing and cleanup of both UI surfaces.

const CARD_INFO_OVERLAY_SCENE := preload("res://scenes/card_view/card_info_overlay.tscn")

var _card
var _zoom_view_scene: PackedScene
var _card_info_overlay: CardInfoOverlay = null
var _zoom_overlay: CanvasLayer = null


func configure(card, zoom_view_scene: PackedScene) -> void:
	_card = card
	_zoom_view_scene = zoom_view_scene


func show_info(show_info: bool, display_only: bool, info_enabled: bool) -> void:
	if _card == null:
		return
	if show_info:
		if (display_only and not info_enabled) or _card.card_instance == null or _card.card_instance.card_data == null:
			return
		var overlay := _get_card_info_overlay()
		if overlay != null:
			overlay.show_for_card(_card)
	elif _card_info_overlay != null and is_instance_valid(_card_info_overlay):
		_card_info_overlay.hide_for_card(_card)


func show_zoom(display_only: bool, zoom_enabled: bool) -> bool:
	if _card == null or (display_only and not zoom_enabled):
		return false
	if _zoom_overlay != null and is_instance_valid(_zoom_overlay):
		return false
	if _zoom_view_scene == null:
		push_error("CardInfoController requires a zoom view scene")
		return false

	var root: Node = _card.get_tree().current_scene
	if root == null:
		return false

	_card._set_card_state(CardEntity.State.ZOOMED)
	show_info(false, display_only, false)

	_zoom_overlay = CanvasLayer.new()
	_zoom_overlay.layer = RenderPriority.CARD_ZOOM_OVERLAY
	_zoom_overlay.name = "CardZoomOverlay"
	root.add_child(_zoom_overlay)
	_card._zoom_overlay = _zoom_overlay

	var background := ColorRect.new()
	background.name = "ZoomBg"
	background.color = Color("070b12b8")
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	_zoom_overlay.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var zoom_view := _zoom_view_scene.instantiate()
	zoom_view.name = "ZoomView"
	zoom_view.set_data(_card.card_instance)
	background.add_child(zoom_view)
	zoom_view.set_anchors_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	_center_zoom_view(zoom_view, background)
	zoom_view.resized.connect(_center_zoom_view.bind(zoom_view, background))
	background.resized.connect(_center_zoom_view.bind(zoom_view, background))
	background.gui_input.connect(_on_zoom_background_input.bind(background))
	_card.set_process_input(true)
	return true


func hide_zoom() -> void:
	if _card != null:
		_card.set_process_input(false)
	if _zoom_overlay != null and is_instance_valid(_zoom_overlay):
		_zoom_overlay.queue_free()
	_zoom_overlay = null
	if _card != null:
		_card._zoom_overlay = null
		if _card.state == CardEntity.State.ZOOMED:
			_card._set_card_state(CardEntity.State.NORMAL)


func handle_unhandled_input(event: InputEvent) -> void:
	if _card != null and _card.state == CardEntity.State.ZOOMED and event.is_action_pressed("ui_cancel"):
		hide_zoom()


func cleanup() -> void:
	show_info(false, false, false)
	hide_zoom()


func _get_card_info_overlay() -> CardInfoOverlay:
	if _card_info_overlay != null and is_instance_valid(_card_info_overlay):
		return _card_info_overlay

	_card_info_overlay = CARD_INFO_OVERLAY_SCENE.instantiate() as CardInfoOverlay
	if _card_info_overlay == null:
		push_error("CardInfoController could not instantiate CardInfoOverlay")
		return null
	_card_info_overlay.name = "CardInfoOverlay"
	_card.add_child(_card_info_overlay)
	_card._card_info_overlay = _card_info_overlay
	return _card_info_overlay


func _center_zoom_view(zoom_view: Control, background: Control) -> void:
	zoom_view.position = (background.size - zoom_view.size) * 0.5


func _on_zoom_background_input(event: InputEvent, background: ColorRect) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var zoom_view := background.get_node_or_null("ZoomView") as Control
	if zoom_view != null and zoom_view.get_global_rect().has_point(event.position):
		return
	hide_zoom()

