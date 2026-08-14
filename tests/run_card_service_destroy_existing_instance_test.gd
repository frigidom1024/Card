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
	_expect(service.configure(CARD_SCENE, hand_zone, drag_layer), "service configures before destruction")

	var card := CARD_SCENE.instantiate() as Card
	var card_inst := CardInstance.new(CardData.new())
	card.bind_card_inst(card_inst)
	card.bind_drag_layer(drag_layer)
	_expect(hand_zone.add_card(card), "fixture adds Card to HandZone")
	_expect(service.register_existing_instance(card_inst, card), "fixture registers the exact pair")

	var other_card := CARD_SCENE.instantiate() as Card
	host.add_child(other_card)
	other_card.bind_card_inst(card_inst)
	_expect(not service.can_destroy_existing_instance(card_inst, other_card), "prevalidation rejects another view for the same instance")
	_expect(not service.destroy_existing_instance(card_inst, other_card), "destruction rejects a mismatched Card view")
	other_card.queue_free()

	_expect(service.can_destroy_existing_instance(card_inst, card), "prevalidation accepts the registered exact pair")
	_expect(service.destroy_existing_instance(card_inst, card), "destruction removes the registered exact pair")
	_expect(not service.get_instances().has(card_inst) and not service.get_card_views().has(card), "destruction removes exact tracking")
	_expect(card_inst.cur_zone == CardInstance.ZONE.DISCARD, "destroyed CardInstance is marked discarded")
	_expect(card_inst.battlefield_pos == Vector2i(-1, -1) and card_inst.direction == 0, "destruction clears board state on CardInstance")
	_expect(card.drag_layer == null, "destroyed Card clears its drag layer binding")
	await process_frame
	_expect(not is_instance_valid(card), "destroyed Card is freed at frame end")

	host.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
