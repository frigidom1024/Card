extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")
const HAND_SCENE := preload("res://scenes/zone/handzone.tscn")
const DRAGGER_SCENE := preload("res://scenes/drag_layer/dragger_layer.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node.new()
	root.add_child(host)
	var hand_zone := HAND_SCENE.instantiate() as HandZone
	var drag_layer := DRAGGER_SCENE.instantiate() as DraggerLayer
	host.add_child(hand_zone)
	host.add_child(drag_layer)
	var service := RunCardService.new()
	_expect(service.configure(CARD_SCENE, hand_zone, drag_layer), "service configures for exact-instance registration")

	var card := CARD_SCENE.instantiate() as Card
	var card_inst := CardInstance.new(CardData.new())
	card.bind_card_inst(card_inst)
	card.bind_drag_layer(drag_layer)
	_expect(hand_zone.add_card(card), "fixture moves purchased Card into HandZone before source commit")
	_expect(service.register_existing_instance(card_inst, card), "service registers an existing exact CardInstance/Card pair")
	_expect(service.get_instances() == [card_inst], "registration preserves exact CardInstance identity")
	_expect(service.get_card_views() == [card], "registration preserves exact Card identity")
	_expect(service.get_entities() == [card], "compatibility getter returns Card views rather than CardEntity")
	_expect(card_inst.cur_zone == CardInstance.ZONE.HAND, "registered purchased instance remains in HAND")
	_expect(service.register_existing_instance(card_inst, card), "registering the same exact pair is idempotent")
	_expect(service.get_instances().size() == 1 and service.get_card_views().size() == 1, "idempotent registration does not duplicate ownership")

	var conflicting_card := CARD_SCENE.instantiate() as Card
	host.add_child(conflicting_card)
	conflicting_card.bind_card_inst(card_inst)
	_expect(not service.register_existing_instance(card_inst, conflicting_card), "same CardInstance cannot be registered to another Card")
	conflicting_card.queue_free()

	service.clear()
	await process_frame
	_expect(service.get_instances().is_empty() and service.get_card_views().is_empty(), "clear releases exact tracking")
	_expect(not is_instance_valid(card), "clear frees registered run-owned Card views")
	host.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
