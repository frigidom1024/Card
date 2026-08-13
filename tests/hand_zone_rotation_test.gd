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
	zone.position = Vector2(100.0, 100.0)
	zone.size = Vector2(500.0, 220.0)
	zone.rot_max = 10.0
	zone.rot_growth = 0.5
	root.add_child(zone)

	var first := CARD_SCENE.instantiate() as Card
	var second := CARD_SCENE.instantiate() as Card
	var third := CARD_SCENE.instantiate() as Card
	zone.add_card(first)
	zone.add_card(second)
	zone.add_card(third)
	await process_frame

	var expected_side_rotation := deg_to_rad(zone.rot_max)
	_expect(absf(first.rotation + expected_side_rotation) <= TOLERANCE, "leftmost Card rotates by the configured degree amount")
	_expect(absf(second.rotation) <= TOLERANCE, "center Card remains upright")
	_expect(absf(third.rotation - expected_side_rotation) <= TOLERANCE, "rightmost Card rotates in the opposite direction")
	_expect(first.rotation * third.rotation < 0.0, "side Card rotations have opposite signs")

	zone.remove_card(third)
	await process_frame
	var expected_two_card_rotation: float = expected_side_rotation * zone.rot_growth
	_expect(absf(first.rotation + expected_two_card_rotation) <= TOLERANCE, "two-card hands use the growth-scaled side rotation")
	_expect(absf(second.rotation - expected_two_card_rotation) <= TOLERANCE, "two-card hands keep opposite growth-scaled rotations")

	zone.free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)