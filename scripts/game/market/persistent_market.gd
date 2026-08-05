class_name PersistentMarket
extends Control


signal purchase_requested(slot_index: int)
signal reclaim_requested(card: CardEntity)
signal refresh_requested


var _state
var _player: PlayerData
var _pricing: Object
var drag_layer
var _slot_previews: Array[CardEntity] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cache_offer_previews()
	_apply_visuals()
	_refresh()


func configure(state, player: PlayerData, pricing: Object) -> void:
	_state = state
	_player = player
	_pricing = pricing
	_refresh()


func set_drag_layer(layer) -> void:
	drag_layer = layer
	for preview in _slot_previews:
		if preview != null and is_instance_valid(preview):
			preview.drag_layer = layer


func get_offer_slot_for_card(card: CardEntity) -> int:
	for slot_index in _slot_previews.size():
		if _slot_previews[slot_index] == card:
			return slot_index
	return -1


func restore_offer_card(card: CardEntity, slot_index: int) -> void:
	if card == null or slot_index < 0 or slot_index >= 3:
		return
	var slot := _offer_slot(slot_index)
	if slot == null:
		return
	card.reparent(slot)
	card.position = Vector2(slot.size.x * 0.5, 112.0)
	card.scale = Vector2.ONE
	card.z_index = RenderPriority.CARD_BASE
	if slot_index >= _slot_previews.size():
		_slot_previews.resize(3)
	_slot_previews[slot_index] = card


func is_over_reclaim_target(global_position: Vector2) -> bool:
	var reclaim_area := get_node_or_null("ReclaimArea") as Control
	return reclaim_area != null and reclaim_area.get_global_rect().has_point(global_position)


func show_message(message: String, is_error := false) -> void:
	var hint := get_node_or_null("ReclaimArea/HintLabel") as Label
	if hint == null:
		return
	hint.text = message
	hint.add_theme_color_override("font_color", Color("d67b68") if is_error else Color("a8a18f"))


func set_offer_card(slot_index: int, card_data: CardData) -> void:
	var preview := _card_preview(slot_index)
	if preview == null:
		return
	preview.bind_instance(CardInstance.new(card_data))
	preview.drag_layer = drag_layer
	preview.set_market_offer_mode(true)


func refresh_display() -> void:
	_refresh()


func _refresh() -> void:
	var refresh_label := get_node_or_null("HeaderRow/RefreshCostLabel") as Label
	if refresh_label != null:
		var refresh_cost: int = _pricing.get_refresh_cost(_build_context()) if _pricing != null else 1
		refresh_label.text = "%d GOLD" % refresh_cost

	for slot_index in 3:
		var card_data: CardData = _state.get_offer(slot_index) if _state != null else null
		var slot := _offer_slot(slot_index)
		if slot != null:
			slot.visible = card_data != null
		if card_data == null:
			continue
		set_offer_card(slot_index, card_data)
		var price_label := slot.get_node_or_null("PriceLabel") as Label if slot != null else null
		if price_label != null:
			var purchase_price: int = _pricing.get_purchase_price(card_data, _build_context()) if _pricing != null else card_data.value
			price_label.text = "%d GOLD" % purchase_price


func _build_context():
	var context_script := load("res://scripts/game/market/market_price_context.gd")
	var context = context_script.new()
	context.player = _player
	context.market_state = _state
	return context


func _cache_offer_previews() -> void:
	_slot_previews.clear()
	for slot_index in 3:
		var slot := _offer_slot(slot_index)
		_slot_previews.append(slot.get_node_or_null("CardPreview") as CardEntity if slot != null else null)


func _offer_slot(slot_index: int) -> Control:
	return get_node_or_null("OfferRow/OfferSlot%d" % (slot_index + 1)) as Control


func _card_preview(slot_index: int) -> CardEntity:
	if slot_index >= 0 and slot_index < _slot_previews.size() and is_instance_valid(_slot_previews[slot_index]):
		return _slot_previews[slot_index]
	var slot := _offer_slot(slot_index)
	return slot.get_node_or_null("CardPreview") as CardEntity if slot != null else null


func _apply_visuals() -> void:
	var panel := get_node_or_null("Backdrop") as Panel
	if panel != null:
		panel.add_theme_stylebox_override("panel", _make_panel_style(Color("0a1019e8"), 8, Color("7f6b42"), 1))

	var header := get_node_or_null("HeaderRow") as Panel
	if header != null:
		header.add_theme_stylebox_override("panel", _make_panel_style(Color("151d27f0"), 6, Color("6f6041"), 1))

	var refresh_button := get_node_or_null("HeaderRow/RefreshButton") as Button
	if refresh_button != null:
		refresh_button.add_theme_stylebox_override("normal", _make_panel_style(Color("332f22"), 4, Color("a58b50"), 1))
		refresh_button.add_theme_stylebox_override("hover", _make_panel_style(Color("4a422d"), 4, Color("d2b76d"), 1))
		refresh_button.add_theme_stylebox_override("pressed", _make_panel_style(Color("211e17"), 4, Color("d2b76d"), 1))

	var reclaim_area := get_node_or_null("ReclaimArea") as Panel
	if reclaim_area != null:
		reclaim_area.add_theme_stylebox_override("panel", _make_panel_style(Color("161b23cc"), 6, Color("6e6250"), 1))

	for slot_index in 3:
		var slot := _offer_slot(slot_index)
		if slot != null:
			slot.add_theme_stylebox_override("panel", _make_panel_style(Color("101720"), 6, Color("46515b"), 1))


func _make_panel_style(background: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	return style


func _on_refresh_button_pressed() -> void:
	refresh_requested.emit()
