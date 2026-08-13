extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")

class TrackingDraggerLayer:
	extends DraggerLayer

	var update_count := 0
	var last_card: Card

	func update_drag(card: Card) -> void:
		update_count += 1
		last_card = card


var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var card := CARD_SCENE.instantiate() as Card
	root.add_child(card)
	await process_frame

	var data := CardData.new()
	var card_inst := CardInstance.new(data)

	_expect(card.has_method("bind_card_inst"), "Card exposes bind_card_inst")
	_expect(card.has_method("get_card_inst"), "Card exposes get_card_inst")
	if card.has_method("bind_card_inst") and card.has_method("get_card_inst"):
		card.bind_card_inst(card_inst)
		_expect(card.get_card_inst() == card_inst, "Card keeps the exact CardInstance identity")
		card.bind_card_inst(null)
		_expect(card.get_card_inst() == null, "binding null clears the CardInstance")

	var dragger := TrackingDraggerLayer.new()
	root.add_child(dragger)
	card.bind_drag_layer(dragger)
	card.dragging = true
	card.call("_update_drag", Vector2.ZERO)
	_expect(dragger.update_count == 1, "Card notifies DraggerLayer during drag movement")
	_expect(dragger.last_card == card, "Card passes itself to DraggerLayer.update_drag")

	card.free()
	dragger.free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
