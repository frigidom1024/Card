extends SceneTree

const CardEntityScene := preload("res://scenes/card_view/card_entity.tscn")

var _failure_count := 0

func _init() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var host := Node2D.new()
	root.add_child(host)
	var card := CardEntityScene.instantiate() as CardEntity
	host.add_child(card)
	await process_frame

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	card._on_input_event(root, press, 0)
	_expect(card._dragging, "CardEntity compatibility drag state mirrors controller after routed input starts drag")
	_expect(card.get_node("CardInteractionController").is_dragging(), "interaction controller owns the active drag state")

	card.cancel_drag()
	_expect(not card._dragging, "CardEntity compatibility drag state clears after cancellation")
	_expect(not card.get_node("CardInteractionController").is_dragging(), "interaction controller clears the active drag state")

	host.free()
	quit(1 if _failure_count > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
