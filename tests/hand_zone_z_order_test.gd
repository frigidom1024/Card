extends SceneTree

const HAND_ZONE_SCENE := preload("res://scenes/zone/handzone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var zone := HAND_ZONE_SCENE.instantiate() as HandZone
	zone.set_anchors_preset(Control.PRESET_TOP_LEFT)
	zone.size = Vector2(500.0, 220.0)
	root.add_child(zone)

	var first := CARD_SCENE.instantiate() as Card
	var second := CARD_SCENE.instantiate() as Card
	var third := CARD_SCENE.instantiate() as Card
	zone.add_card(first)
	zone.add_card(second)
	zone.add_card(third)
	await process_frame

	_expect(first.z_index < second.z_index, "second Card renders above first Card")
	_expect(second.z_index < third.z_index, "third Card renders above second Card")

	# Hover state must not reverse the hand's left-to-right stacking order.
	first._on_mouse_entered()
	_expect(first.z_index < third.z_index, "hovering the left Card does not cover the right Card")
	first._on_mouse_exited()

	zone.free()
	quit(1 if _failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)