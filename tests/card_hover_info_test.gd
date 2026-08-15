extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")
const HOVER_INFO_SCENE := preload("res://scenes/card/hover_info.tscn")
const HUD_SCENE := preload("res://scenes/game/hud/hud.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_hud_owns_shared_hover_layer()
	await _test_hover_info_binds_and_renders_card_instance()
	await _test_hover_info_renders_pixel_reference_layout()
	await _test_card_hover_shows_panel_on_the_right_and_hides()
	await _test_card_hover_flips_panel_to_the_left_at_viewport_edge()
	quit(1 if _failures > 0 else 0)


func _test_hud_owns_shared_hover_layer() -> void:
	var hud := HUD_SCENE.instantiate() as Control
	root.add_child(hud)
	await process_frame

	var layer := hud.get_node_or_null("CardHoverLayer") as Control
	var hover_info := hud.get_node_or_null("CardHoverLayer/HoverInfo") as Control
	_expect(layer != null, "HUD owns a CardHoverLayer for shared card information")
	_expect(hover_info != null, "CardHoverLayer owns the shared HoverInfo instance")
	if layer != null:
		_expect(
			layer.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"CardHoverLayer does not intercept pointer input",
		)
		_expect(layer.z_index >= 1000, "CardHoverLayer renders above ordinary HUD content")
	if hover_info != null:
		_expect(not hover_info.visible, "shared HoverInfo starts hidden")
		_expect(
			hover_info.is_in_group("card_hover_info"),
			"shared HoverInfo is discoverable through the card_hover_info group",
		)
		_expect(
			_all_controls_ignore_mouse(hover_info),
			"HoverInfo and all of its Control descendants ignore pointer input",
		)

	hud.free()
	await process_frame


func _test_hover_info_binds_and_renders_card_instance() -> void:
	var hover_info := HOVER_INFO_SCENE.instantiate() as Control
	root.add_child(hover_info)
	await process_frame

	var data := CardData.new()
	data.max_points = 7
	data.armor = 2
	var rule := CardRule.new()
	rule.description = "Gain one point after placement"
	data.effect_rules.append(rule)
	var instance := CardInstance.new(data)
	instance.current_points = 5
	instance.current_armor = 3

	_expect(hover_info.has_method("set_inst"), "HoverInfo exposes CardInstance binding")
	if not hover_info.has_method("set_inst"):
		hover_info.free()
		await process_frame
		return
	hover_info.call("set_inst", instance)
	_expect(
		hover_info.get("card_inst") == instance,
		"HoverInfo stores the CardInstance passed to set_inst",
	)
	if hover_info.get("card_inst") != instance:
		hover_info.free()
		await process_frame
		return

	hover_info.call("refresh_info")
	await process_frame
	var labels := _collect_labels(hover_info)
	_expect(labels.has("5"), "HoverInfo renders the current point value")
	_expect(labels.has("3"), "HoverInfo renders the current armor value")
	_expect(
		labels.has(rule.description),
		"HoverInfo renders each card rule description",
	)

	hover_info.free()
	await process_frame


func _test_hover_info_renders_pixel_reference_layout() -> void:
	var hover_info := HOVER_INFO_SCENE.instantiate() as Control
	root.add_child(hover_info)
	await process_frame

	var data := CardData.new()
	data.card_name = "Ancient Amulet"
	data.description = "An old amulet carved by forgotten hands."
	data.rarity = CardData.Rarity.EPIC
	data.tags = [CardData.CardTag.ITEM]
	var rule := CardRule.new()
	rule.description = "Magic find increased"
	data.effect_rules.append(rule)
	var instance := CardInstance.new(data)
	instance.current_points = 5
	instance.current_armor = 3

	hover_info.call("set_inst", instance)
	hover_info.call("refresh_info")
	await process_frame

	var rarity_label := hover_info.get_node_or_null(
		"Panel/Margin/Layout/BadgeRow/RarityBadge/RarityLabel"
	) as Label
	var category_label := hover_info.get_node_or_null(
		"Panel/Margin/Layout/BadgeRow/CategoryBadge/CategoryLabel"
	) as Label
	var title_panel := hover_info.get_node_or_null(
		"Panel/Margin/Layout/TitlePanel"
	) as PanelContainer
	var title_label := hover_info.get_node_or_null(
		"Panel/Margin/Layout/TitlePanel/TitleLabel"
	) as Label
	var description_label := hover_info.get_node_or_null(
		"Panel/Margin/Layout/DescriptionLabel"
	) as Label
	var point_value := hover_info.get_node_or_null(
		"Panel/Margin/Layout/Stats/PointRow/ValueLabel"
	) as Label
	var armor_value := hover_info.get_node_or_null(
		"Panel/Margin/Layout/Stats/ArmorRow/ValueLabel"
	) as Label

	_expect(rarity_label != null, "HoverInfo exposes a rarity badge label")
	_expect(category_label != null, "HoverInfo exposes a category badge label")
	_expect(title_panel != null, "HoverInfo exposes the high-contrast title panel")
	_expect(title_label != null, "HoverInfo exposes the card title label")
	_expect(description_label != null, "HoverInfo exposes the description label")
	_expect(point_value != null, "HoverInfo exposes a dedicated point value label")
	_expect(armor_value != null, "HoverInfo exposes a dedicated armor value label")

	if rarity_label != null:
		_expect(rarity_label.text == "EPIC", "rarity badge renders the card rarity")
	if category_label != null:
		_expect(category_label.text == "ITEM", "category badge renders the semantic card tag")
	if title_label != null:
		_expect(title_label.text == data.card_name, "title panel renders the card name")
	if description_label != null:
		_expect(
			description_label.text == data.description,
			"description area renders the card description",
		)
		_expect(
			description_label.autowrap_mode != TextServer.AUTOWRAP_OFF,
			"description area wraps long text",
		)
	if point_value != null:
		_expect(point_value.text == "5", "point row renders current points")
	if armor_value != null:
		_expect(armor_value.text == "3", "armor row renders current armor")
	if title_panel != null:
		var title_style := title_panel.get_theme_stylebox("panel") as StyleBoxFlat
		_expect(title_style != null, "title panel uses a solid high-contrast style")
		if title_style != null:
			_expect(
				title_style.bg_color.get_luminance() > 0.85,
				"title panel uses the bright reference-image treatment",
			)

	var labels := _collect_labels(hover_info)
	_expect(labels.has(rule.description), "rules remain visible in the pixel layout")

	hover_info.free()
	await process_frame


func _test_card_hover_shows_panel_on_the_right_and_hides() -> void:
	var fixture := await _make_hover_fixture(Vector2(300.0, 200.0))
	var hud := fixture.hud as Control
	var card := fixture.card as Card
	var hover_info := fixture.hover_info as Control
	if hover_info == null:
		hud.free()
		await process_frame
		return

	card.mouse_entered.emit()
	await process_frame
	var card_rect := _screen_rect(card)
	var hover_origin := hover_info.get_global_transform_with_canvas() * Vector2.ZERO
	_expect(hover_info.visible, "entering a card shows the shared HoverInfo")
	_expect(
		hover_info.get("card_inst") == card.card_inst,
		"entering a card binds that card's instance to the shared HoverInfo",
	)
	_expect(
		_all_controls_ignore_mouse(hover_info),
		"refreshed HoverInfo content continues to ignore pointer input",
	)
	_expect(
		hover_origin.x > card_rect.end.x,
		"HoverInfo is placed to the right of a card when space is available",
	)

	card.mouse_exited.emit()
	_expect(not hover_info.visible, "leaving a card hides the shared HoverInfo")

	card.mouse_entered.emit()
	var drag_event := InputEventMouseButton.new()
	drag_event.button_index = MOUSE_BUTTON_LEFT
	drag_event.pressed = true
	drag_event.position = card.size * 0.5
	card.gui_input.emit(drag_event)
	_expect(not hover_info.visible, "starting a card drag hides the shared HoverInfo")

	hud.free()
	await process_frame


func _test_card_hover_flips_panel_to_the_left_at_viewport_edge() -> void:
	var viewport_width := root.get_visible_rect().size.x
	var fixture := await _make_hover_fixture(Vector2(viewport_width - 100.0, 200.0))
	var hud := fixture.hud as Control
	var card := fixture.card as Card
	var hover_info := fixture.hover_info as Control
	if hover_info == null:
		hud.free()
		await process_frame
		return

	card.mouse_entered.emit()
	await process_frame
	var card_rect := _screen_rect(card)
	var hover_origin := hover_info.get_global_transform_with_canvas() * Vector2.ZERO
	_expect(
		hover_origin.x + hover_info.size.x < card_rect.position.x,
		"HoverInfo flips to the left when the card's right side has no room",
	)

	hud.free()
	await process_frame


func _make_hover_fixture(card_position: Vector2) -> Dictionary:
	var hud := HUD_SCENE.instantiate() as Control
	root.add_child(hud)
	await process_frame
	var card := CARD_SCENE.instantiate() as Card
	var data := CardData.new()
	data.max_points = 4
	data.armor = 1
	card.bind_card_inst(CardInstance.new(data))
	card.position = card_position
	card.target_position = card_position
	hud.add_child(card)
	await process_frame
	return {
		"hud": hud,
		"card": card,
		"hover_info": hud.get_node_or_null("CardHoverLayer/HoverInfo") as Control,
	}


func _screen_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	var corners := [
		transform * Vector2.ZERO,
		transform * Vector2(control.size.x, 0.0),
		transform * control.size,
		transform * Vector2(0.0, control.size.y),
	]
	var minimum := corners[0] as Vector2
	var maximum := corners[0] as Vector2
	for corner: Vector2 in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


func _collect_labels(node: Node) -> Array[String]:
	var labels: Array[String] = []
	if node is Label:
		labels.append((node as Label).text)
	for child in node.get_children():
		labels.append_array(_collect_labels(child))
	return labels


func _all_controls_ignore_mouse(node: Node) -> bool:
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child in node.get_children():
		if not _all_controls_ignore_mouse(child):
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
