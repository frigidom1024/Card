extends SceneTree

const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var card := CardEntityScene.instantiate() as CardEntity
	root.add_child(card)
	await process_frame

	_expect(card.has_method("set_market_offer_mode"), "CardEntity exposes market offer mode")
	if card.has_method("set_market_offer_mode"):
		card.call("set_market_offer_mode", true)
		_expect(card.call("is_market_offer"), "market offer mode is enabled")
		_expect(card.input_pickable, "market offer remains input-pickable")
		_expect(card.call("rotate_while_dragging") == false, "market offer cannot rotate")

	card.queue_free()
	await process_frame
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)