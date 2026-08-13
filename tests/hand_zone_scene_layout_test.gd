extends SceneTree

const TEST_SCENE := preload("res://scenes/drag_layer/test.tscn")
const TOLERANCE := 0.01

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := TEST_SCENE.instantiate() as Node2D
	root.add_child(scene)
	await process_frame
	await process_frame

	var zone := scene.get_node("Handzone") as HandZone
	zone.float_amplitude = 0.0
	zone.refresh_hand()
	_expect(zone != null, "test scene contains a HandZone")
	if zone == null:
		quit(1)
		return

	_expect(zone.cards.size() == 2, "HandZone registers its pre-existing Card children")
	if zone.cards.size() >= 2:
		var first := zone.cards[0]
		var second := zone.cards[1]
		var step := first.size.x - zone.card_overlap
		_expect(absf(second.target_position.x - first.target_position.x - step) <= TOLERANCE, "test scene cards use width-minus-overlap spacing")
		_expect(absf(first.target_position.y - zone.card_row_y) <= TOLERANCE, "test scene cards use the configured hand row")
		_expect(absf(second.target_position.y - zone.card_row_y) <= TOLERANCE, "test scene cards use the configured hand row")

	scene.free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)