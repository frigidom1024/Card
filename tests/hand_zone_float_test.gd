extends SceneTree

const HAND_ZONE_SCENE := preload("res://scenes/zone/handzone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const TOLERANCE := 0.0001

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var zone := HAND_ZONE_SCENE.instantiate() as HandZone
	zone.set_anchors_preset(Control.PRESET_TOP_LEFT)
	zone.size = Vector2(500.0, 220.0)
	zone.float_amplitude = 10.0
	zone.float_phase_offset = PI * 0.5
	zone.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(zone)

	var first := CARD_SCENE.instantiate() as Card
	var second := CARD_SCENE.instantiate() as Card
	var third := CARD_SCENE.instantiate() as Card
	zone.add_card(first)
	zone.add_card(second)
	zone.add_card(third)
	zone._float_time = PI * 0.5
	zone.refresh_hand()

	_expect(absf(first.target_position.y - (zone.card_row_y + zone.float_amplitude)) <= TOLERANCE, "first Card follows the sine-wave vertical offset")
	_expect(absf(second.target_position.y - zone.card_row_y) <= TOLERANCE, "second Card is at the sine-wave midpoint")
	_expect(absf(third.target_position.y - (zone.card_row_y - zone.float_amplitude)) <= TOLERANCE, "third Card follows the opposite sine-wave offset")

	first.dragging = true
	var dragged_y := first.target_position.y
	zone._float_time = PI
	zone.refresh_hand()
	_expect(absf(first.target_position.y - dragged_y) <= TOLERANCE, "dragging Card keeps its target position while the hand floats")

	zone.free()
	quit(1 if _failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)