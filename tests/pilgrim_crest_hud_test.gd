extends SceneTree

const PilgrimCrestHudScene = preload("res://scenes/game/pilgrim_crest_hud.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var hud := PilgrimCrestHudScene.instantiate() as PilgrimCrestHud
	var editor_position := Vector2(1620.0, 28.0)
	hud.position = editor_position
	root.add_child(hud)
	await process_frame

	hud.set_display_context("PILGRIM", "LAST KNIGHT", "RIBWOOD")
	hud.set_vitality(34, 50)
	hud.set_faith(3)
	_expect(hud.has_method("set_gold"), "HUD exposes a gold setter")
	if hud.has_method("set_gold"):
		hud.call("set_gold", 17)
	hud.set_temporary_status("")
	_expect(hud.position == editor_position, "player HUD preserves the position authored by its parent scene")
	_expect(hud.size == Vector2(584, 224), "player HUD matches the persistent market width")

	_expect((hud.get_node("IdentityLabel") as Label).get_theme_font_size("font_size") == 20, "HUD enlarges identity text")
	_expect((hud.get_node("SubtitleLabel") as Label).get_theme_font_size("font_size") == 14, "HUD enlarges subtitle text")
	_expect((hud.get_node("MapLabel") as Label).get_theme_font_size("font_size") == 15, "HUD enlarges map text")
	_expect((hud.get_node("VitalityTitle") as Label).get_theme_font_size("font_size") == 15, "HUD enlarges vitality caption")
	_expect((hud.get_node("VitalityValue") as Label).get_theme_font_size("font_size") == 32, "HUD preserves vitality emphasis")
	_expect((hud.get_node("FaithSeal/FaithValue") as Label).get_theme_font_size("font_size") == 17, "HUD enlarges faith text")
	_expect((hud.get_node("GoldSeal/GoldValue") as Label).get_theme_font_size("font_size") == 17, "HUD enlarges gold text")
	_expect((hud.get_node("StatusRow/StatusLabel") as Label).get_theme_font_size("font_size") == 15, "HUD enlarges status text")
	_expect((hud.get_node("FaithSeal") as Panel).size == Vector2(262, 30), "HUD expands faith seal for readable text")
	_expect((hud.get_node("GoldSeal") as Panel).size == Vector2(262, 30), "HUD expands gold seal for readable text")
	_expect((hud.get_node("IdentityLabel") as Label).get_theme_color("font_color").get_luminance() > 0.7, "HUD primary text has strong contrast")
	_expect((hud.get_node("MapLabel") as Label).get_theme_color("font_color").get_luminance() > 0.5, "HUD accent text has readable contrast")

	_expect((hud.get_node("VitalityValue") as Label).text == "34 / 50", "HUD formats vitality")
	_expect((hud.get_node("VitalityBar") as ProgressBar).value == 34.0, "HUD fills vitality bar")
	_expect((hud.get_node("FaithSeal/FaithValue") as Label).text == "FAITH · 3", "HUD formats faith")
	var gold_value := hud.get_node_or_null("GoldSeal/GoldValue") as Label
	_expect(gold_value != null, "HUD exposes a gold value label")
	if gold_value != null:
		_expect(gold_value.text == "GOLD · 17", "HUD formats gold")
	_expect(not (hud.get_node("StatusRow") as Control).visible, "empty status collapses status row")

	hud.set_temporary_status("CURSE · BONE CHILL")
	_expect((hud.get_node("StatusRow") as Control).visible, "active status shows status row")
	_expect((hud.get_node("StatusRow/StatusLabel") as Label).text == "CURSE · BONE CHILL", "HUD keeps supplied status copy")
	_expect(_all_controls_ignore_mouse(hud), "HUD controls do not capture card input")

	hud.queue_free()
	await process_frame
	quit(0 if _failure_count == 0 else 1)


func _all_controls_ignore_mouse(node: Node) -> bool:
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child in node.get_children():
		if not _all_controls_ignore_mouse(child):
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
