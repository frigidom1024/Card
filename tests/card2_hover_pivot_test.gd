extends SceneTree

const CardScene := preload("res://scenes/card/card2.tscn")
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var card := CardScene.instantiate() as Button
	root.add_child(card)
	await process_frame

	_expect(card.pivot_offset.is_equal_approx(card.size * 0.5), "card hover scale uses the card center as pivot")

	card.size = Vector2(120.0, 200.0)
	await process_frame
	_expect(card.pivot_offset.is_equal_approx(card.size * 0.5), "pivot stays centered after card resize")

	card.free()
	quit(1 if _failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
