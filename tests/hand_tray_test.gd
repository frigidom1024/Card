extends SceneTree

const HandTrayScene = preload("res://scenes/game/hand_tray.tscn")
const HandAreaScript = preload("res://scripts/game/hand.gd")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const FLOAT_TOLERANCE := 0.01
const DEFAULT_TRAY_WIDTH := 1536.0
const DEFAULT_TRAY_X := 192.0
const DEFAULT_TRAY_Y := 876.0
const DEFAULT_TRAY_HEIGHT := 224.0
const METADATA_INSET := Vector2(48.0, 32.0)
const EXPECTED_TRAY_COLOR := Color("0a1220d9")
const EXPECTED_LINING_COLOR := Color("9b90736b")
const EXPECTED_TRIM_COLOR := Color("b7964f99")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var tray := HandTrayScene.instantiate() as HandTray
	root.add_child(tray)
	await process_frame
	_expect_all_controls_ignore_input(tray)
	_expect(tray.z_index < RenderPriority.CARD_BASE, "hand tray renders behind normal hand cards")
	_expect(tray.get_node_or_null("OuterTray") is Panel, "hand tray exposes an editable outer tray panel")
	_expect(tray.get_node_or_null("InnerLining") is Panel, "hand tray exposes a bone-paper inner lining")
	_expect(tray.get_node_or_null("TopTrim") is ColorRect, "hand tray exposes an antique-gold top trim")
	_expect(tray.get_node_or_null("LeftClasp") is ColorRect, "hand tray exposes an editable left clasp")
	_expect(tray.get_node_or_null("RightClasp") is ColorRect, "hand tray exposes an editable right clasp")
	_expect(tray.get_node_or_null("HandCount") is Label, "hand tray exposes an editable hand count label")
	_expect(tray.get_node_or_null("FutureInfoAnchor") is Control, "hand tray exposes an editable future info anchor")
	_expect_default_layout(tray)
	_expect_metadata_layout(tray)
	_expect_tray_appearance(tray)
	tray.set_hand_count(4, 10)
	var hand_count := tray.get_node_or_null("HandCount") as Label
	_expect(hand_count != null and hand_count.text == "HAND · 4 / 10", "hand tray renders English current and maximum hand count")
	tray.free()
	_test_hand_count_signal_tracks_add_remove_and_clear()
	quit(1 if _failure_count > 0 else 0)


func _expect_all_controls_ignore_input(node: Node) -> void:
	var control := node as Control
	if control != null:
		_expect(
			control.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"hand tray control %s passes pointer input to hand cards" % control.get_path()
		)
	for child in node.get_children():
		_expect_all_controls_ignore_input(child)


func _expect_default_layout(tray: HandTray) -> void:
	_expect(
		absf(tray.size.x - DEFAULT_TRAY_WIDTH) <= FLOAT_TOLERANCE,
		"hand tray default width is 1536.0 in the 1920-wide design viewport"
	)
	_expect(
		absf(tray.position.x - DEFAULT_TRAY_X) <= FLOAT_TOLERANCE,
		"hand tray default x position is centered at 192.0"
	)
	_expect(
		absf(tray.position.y - DEFAULT_TRAY_Y) <= FLOAT_TOLERANCE,
		"hand tray default y position includes 20.0 pixels of bottom bleed"
	)
	_expect(
		absf(tray.size.y - DEFAULT_TRAY_HEIGHT) <= FLOAT_TOLERANCE,
		"hand tray default height is 224.0 pixels"
	)


func _expect_metadata_layout(tray: HandTray) -> void:
	var hand_count := tray.get_node_or_null("HandCount") as Label
	var future_info_anchor := tray.get_node_or_null("FutureInfoAnchor") as Control
	_expect(
		hand_count != null and hand_count.position == METADATA_INSET,
		"hand count uses the intentional upper-left 48 by 32 pixel inset"
	)
	_expect(
		hand_count != null and hand_count.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
		"hand count is left-aligned"
	)
	_expect(
		hand_count != null and absf(hand_count.size.x - (tray.size.x - METADATA_INSET.x * 2.0)) <= FLOAT_TOLERANCE,
		"hand count spans the tray between matching metadata insets"
	)
	_expect(
		future_info_anchor != null and future_info_anchor.position == Vector2(tray.size.x - METADATA_INSET.x, METADATA_INSET.y),
		"future info anchor uses the matching upper-right inset"
	)


func _expect_tray_appearance(tray: HandTray) -> void:
	_expect(tray.tray_color == EXPECTED_TRAY_COLOR, "hand tray uses the configured navy palette color")
	_expect(tray.lining_color == EXPECTED_LINING_COLOR, "hand tray uses the configured lining palette color")
	_expect(tray.trim_color == EXPECTED_TRIM_COLOR, "hand tray uses the configured antique-gold trim color")
	var outer_tray := tray.get_node_or_null("OuterTray") as Panel
	var outer_style := outer_tray.get_theme_stylebox("panel") as StyleBoxFlat if outer_tray != null else null
	_expect(outer_style != null, "outer tray exposes its generated panel style")
	if outer_style != null:
		_expect(outer_style.bg_color == EXPECTED_TRAY_COLOR, "outer tray style uses the tray palette color")
		_expect(outer_style.border_color == EXPECTED_TRIM_COLOR, "outer tray style uses the trim palette color")
		_expect(outer_style.corner_radius_top_left == 12, "outer tray style has the configured rounded corner radius")
	var inner_lining := tray.get_node_or_null("InnerLining") as Panel
	var inner_style := inner_lining.get_theme_stylebox("panel") as StyleBoxFlat if inner_lining != null else null
	_expect(inner_style != null, "inner lining exposes its generated panel style")
	if inner_style != null:
		_expect(inner_style.bg_color == EXPECTED_LINING_COLOR, "inner lining style uses the lining palette color")
		_expect(inner_style.border_color == Color.TRANSPARENT, "inner lining style has no border")
		_expect(inner_style.corner_radius_top_left == 10, "inner lining style has the configured rounded corner radius")
	var top_trim := tray.get_node_or_null("TopTrim") as ColorRect
	_expect(top_trim != null and top_trim.color == EXPECTED_TRIM_COLOR, "top trim uses the trim palette color")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)

func _test_hand_count_signal_tracks_add_remove_and_clear() -> void:
	var hand := HandAreaScript.new() as HandArea
	var emitted_counts: Array[Vector2i] = []
	hand.hand_count_changed.connect(func(current_count: int, max_count: int) -> void:
		emitted_counts.append(Vector2i(current_count, max_count))
	)
	root.add_child(hand)
	var card := CardEntityScene.instantiate() as CardEntity
	_expect(emitted_counts.is_empty(), "hand count signal starts with no emissions")
	_expect(hand.add_card(card, false), "hand accepts a card for count-change coverage")
	_expect(emitted_counts.size() == 1, "successful add emits hand count exactly once")
	_expect(emitted_counts[0] == Vector2i(1, hand.max_hand_size), "adding a card emits the new hand count")
	_expect(hand.remove_card(card, false), "hand removes a card for count-change coverage")
	_expect(emitted_counts.size() == 2, "successful remove emits hand count exactly once")
	_expect(emitted_counts[1] == Vector2i(0, hand.max_hand_size), "removing a card emits the new hand count")
	_expect(hand.add_card(card, false), "hand can add the removed card before clear coverage")
	_expect(emitted_counts.size() == 3, "second successful add emits hand count exactly once")
	_expect(emitted_counts[2] == Vector2i(1, hand.max_hand_size), "second add emits the new hand count")
	hand.clear_hand()
	_expect(emitted_counts.size() == 4, "successful clear emits hand count exactly once")
	_expect(emitted_counts[3] == Vector2i(0, hand.max_hand_size), "clearing the hand emits a zero hand count")
	hand.free()


