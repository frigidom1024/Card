extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := RunCardService.new()
	var card := CARD_SCENE.instantiate() as Card
	root.add_child(card)
	await process_frame
	var card_inst := CardInstance.new(CardData.new())
	card.bind_card_inst(card_inst)
	_expect(service.register_existing_instance(card_inst, card), "fixture registers the exact CardInstance/Card pair")

	_expect(service.has_method("can_destroy_existing_instance"), "RunCardService exposes exact-instance destruction prevalidation")
	_expect(service.has_method("destroy_existing_instance"), "RunCardService exposes exact-instance destruction")
	if service.has_method("can_destroy_existing_instance") and service.has_method("destroy_existing_instance"):
		var other_card := CARD_SCENE.instantiate() as Card
		root.add_child(other_card)
		other_card.bind_card_inst(card_inst)
		_expect(not service.can_destroy_existing_instance(card_inst, other_card), "prevalidation rejects a different Card view for the same instance")
		_expect(not service.destroy_existing_instance(card_inst, other_card), "destruction rejects a mismatched Card view")
		_expect(service.get_instances().has(card_inst) and service.get_card_views().has(card), "failed destruction keeps exact ownership")
		other_card.free()

		_expect(service.can_destroy_existing_instance(card_inst, card), "prevalidation accepts the registered exact pair")
		_expect(service.destroy_existing_instance(card_inst, card), "destruction removes the registered exact pair")
		_expect(not service.get_instances().has(card_inst), "destruction removes the exact CardInstance")
		_expect(not service.get_card_views().has(card), "destruction removes the exact Card view")
		_expect(card_inst.cur_zone == CardInstance.ZONE.DISCARD, "destroyed CardInstance is marked discarded")
		_expect(card.cur_zone == null, "destroyed Card clears its zone reference")
		_expect(card.drag_layer == null, "destroyed Card clears its drag layer reference")
		_expect(not service.destroy_existing_instance(card_inst, card), "destroying the same pair twice is rejected")
		await process_frame
		_expect(not is_instance_valid(card), "destroyed Card view is freed at frame end")

	if is_instance_valid(card):
		card.free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
