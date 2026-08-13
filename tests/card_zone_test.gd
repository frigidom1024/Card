extends SceneTree

const CARD_ZONE_SCENE_PATH := "res://scenes/zone/card_zone.tscn"
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const TOLERANCE := 0.01

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed_scene := load(CARD_ZONE_SCENE_PATH) as PackedScene
	_expect(packed_scene != null, "new CardZone scene exists")
	if packed_scene == null:
		quit(1)
		return

	var zone := packed_scene.instantiate() as CardZone
	zone.set_anchors_preset(Control.PRESET_TOP_LEFT)
	zone.position = Vector2.ZERO
	zone.size = Vector2(400.0, 200.0)
	root.add_child(zone)
	await process_frame

	var first := CARD_SCENE.instantiate() as Card
	var second := CARD_SCENE.instantiate() as Card
	_expect(zone.add_card(first), "CardZone accepts a Card")
	_expect(zone.add_card(second), "CardZone accepts another Card")

	var dragged := CARD_SCENE.instantiate() as Card
	_expect(zone.begin_card_projection(dragged), "CardZone starts a virtual-card projection")
	_expect(zone.update_card_projection(dragged, Vector2(220.0, 80.0)), "CardZone updates a projection from pointer position")
	_expect(zone.get_projected_index() == 1, "CardZone chooses the middle insertion index")
	_expect(zone.get_cards().size() == 2, "projected Card is not yet a stored Card")
	_expect(zone.get_layout_card_count() == 3, "projected Card participates in layout")
	_expect(absf(second.target_position.x - first.target_position.x - 128.0) <= TOLERANCE, "virtual Card pushes the later Card by one extra slot")

	_expect(zone.clear_card_projection(), "CardZone clears the projected layout")
	_expect(zone.get_layout_card_count() == 2, "clearing projection restores layout count")
	_expect(absf(second.target_position.x - first.target_position.x - 64.0) <= TOLERANCE, "clearing projection restores normal overlap")

	zone.clear_cards()
	for card in [first, second, dragged]:
		if is_instance_valid(card):
			card.free()
	zone.free()
	quit(1 if _failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
