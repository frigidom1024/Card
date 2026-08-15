extends SceneTree

const GameInfoScene = preload("res://scenes/game/hud/game_info.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var game_info := GameInfoScene.instantiate() as Control
	root.add_child(game_info)
	await process_frame

	_expect(game_info.has_method("set_vitality"), "GameInfo exposes a vitality setter")
	_expect(game_info.has_method("set_gold"), "GameInfo exposes a gold setter")
	if game_info.has_method("set_vitality"):
		game_info.call("set_vitality", 34, 50)
	if game_info.has_method("set_gold"):
		game_info.call("set_gold", 17)

	var health_number := game_info.get_node_or_null("HeartContainer/HealthNumber") as Label
	_expect(health_number != null, "GameInfo exposes a health value label")
	if health_number != null:
		_expect(health_number.text == "34 / 50", "GameInfo formats current and maximum health")

	var gold_number := game_info.get_node_or_null("GoldNumber") as Label
	_expect(gold_number != null, "GameInfo exposes a gold value label")
	if gold_number != null:
		_expect(gold_number.text == "17", "GameInfo formats current gold")

	_expect(_all_controls_ignore_mouse(game_info), "GameInfo does not block card input")

	game_info.queue_free()
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
	if condition:
		return
	_failure_count += 1
	push_error(message)
