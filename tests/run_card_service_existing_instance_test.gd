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

	_expect(service.has_method("can_register_existing_instance"), "RunCardService exposes exact-instance prevalidation")
	_expect(service.has_method("register_existing_instance"), "RunCardService exposes exact-instance registration")
	_expect(service.has_method("get_card_views"), "RunCardService exposes registered new Card views")
	if service.has_method("register_existing_instance") and service.has_method("get_card_views"):
		_expect(service.register_existing_instance(card_inst, card), "service registers an existing CardInstance/Card pair")
		_expect(service.get_instances().size() == 1 and service.get_instances()[0] == card_inst, "registration preserves exact CardInstance identity")
		_expect(service.get_card_views().size() == 1 and service.get_card_views()[0] == card, "registration tracks the exact Card view separately from CardEntity")
		_expect(service.get_entities().is_empty(), "new Card view is not inserted into legacy CardEntity storage")
		_expect(card_inst.cur_zone == CardInstance.ZONE.HAND, "registered purchased instance is marked as owned in hand")
		_expect(service.register_existing_instance(card_inst, card), "registering the same pair is idempotent")
		_expect(service.get_instances().size() == 1 and service.get_card_views().size() == 1, "idempotent registration does not duplicate ownership")

		var conflicting_card := CARD_SCENE.instantiate() as Card
		root.add_child(conflicting_card)
		conflicting_card.bind_card_inst(card_inst)
		_expect(not service.register_existing_instance(card_inst, conflicting_card), "same CardInstance cannot be registered to a different Card view")
		conflicting_card.free()

		var empty_inst := CardInstance.new(null)
		_expect(not service.register_existing_instance(empty_inst, card), "service rejects an instance without CardData")
		_expect(not service.register_existing_instance(null, card), "service rejects a null CardInstance")
		_expect(not service.register_existing_instance(card_inst, null), "service rejects a null Card view")

		service.clear()
		_expect(service.get_instances().is_empty() and service.get_card_views().is_empty(), "clear releases exact-instance tracking")
		_expect(is_instance_valid(card), "clear does not free Card views owned by their target zone")

	card.free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
