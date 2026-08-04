extends SceneTree

const PilgrimCrestHudScene = preload("res://scenes/game/pilgrim_crest_hud.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var hud := PilgrimCrestHudScene.instantiate() as PilgrimCrestHud
	root.add_child(hud)
	await process_frame

	hud.set_display_context("PILGRIM", "LAST KNIGHT", "RIBWOOD")
	hud.set_vitality(34, 50)
	hud.set_faith(3)
	hud.set_temporary_status("")

	_expect((hud.get_node("VitalityValue") as Label).text == "34 / 50", "HUD formats vitality")
	_expect((hud.get_node("VitalityBar") as ProgressBar).value == 34.0, "HUD fills vitality bar")
	_expect((hud.get_node("FaithSeal/FaithValue") as Label).text == "FAITH · 3", "HUD formats faith")
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
