extends SceneTree

const CARD_ZONE_SCENE := preload("res://scenes/zone/card_zone.tscn")
const DRAGGER_LAYER_SCENE_PATH := "res://scenes/drag_layer/dragger_layer.tscn"

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dragger_scene := load(DRAGGER_LAYER_SCENE_PATH) as PackedScene
	_expect(dragger_scene != null, "new DraggerLayer scene exists")
	if dragger_scene == null:
		quit(1)
		return

	var first_zone := CARD_ZONE_SCENE.instantiate() as CardZone
	first_zone.set_anchors_preset(Control.PRESET_TOP_LEFT)
	first_zone.position = Vector2(0.0, 0.0)
	first_zone.size = Vector2(300.0, 200.0)
	root.add_child(first_zone)

	var second_zone := CARD_ZONE_SCENE.instantiate() as CardZone
	second_zone.set_anchors_preset(Control.PRESET_TOP_LEFT)
	second_zone.position = Vector2(350.0, 0.0)
	second_zone.size = Vector2(300.0, 200.0)
	root.add_child(second_zone)

	var dragger := dragger_scene.instantiate() as DraggerLayer
	root.add_child(dragger)
	await process_frame

	_expect(not dragger.has_method("begin_drag"), "DraggerLayer does not own drag start")
	_expect(not dragger.has_method("update_drag"), "DraggerLayer does not move Cards")
	_expect(not dragger.has_method("end_drag"), "DraggerLayer does not commit drops")

	dragger.register_zone(first_zone)
	dragger.register_zone(second_zone)
	_expect(dragger.get_zone_at(Vector2(50.0, 50.0)) == first_zone, "DraggerLayer detects the first registered CardZone")
	_expect(dragger.get_zone_at(Vector2(400.0, 50.0)) == second_zone, "DraggerLayer detects another CardZone")
	_expect(dragger.get_zone_at(Vector2(700.0, 50.0)) == null, "DraggerLayer reports no zone outside registered bounds")

	dragger.unregister_zone(first_zone)
	_expect(dragger.get_zone_at(Vector2(50.0, 50.0)) == null, "unregistered CardZone no longer participates in detection")

	first_zone.free()
	second_zone.free()
	dragger.free()
	quit(1 if _failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
