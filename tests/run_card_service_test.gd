extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")
const HAND_SCENE := preload("res://scenes/zone/handzone.tscn")
const DRAGGER_SCENE := preload("res://scenes/drag_layer/dragger_layer.tscn")
const REVIVAL_DECK := preload("res://data/starting_decks/revival_starting_deck.tres")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_starting_deck_creates_exact_card_views()
	await _test_grant_and_return_use_hand_zone_without_capacity_rules()
	await _test_forget_untracks_without_freeing()
	quit(1 if _failures > 0 else 0)


func _test_starting_deck_creates_exact_card_views() -> void:
	var fixture := _create_fixture()
	var service: RunCardService = fixture.service
	_expect(service.initialize_starting_deck(REVIVAL_DECK), "service initializes the configured starting deck")
	await process_frame

	var cards := service.get_card_views()
	_expect(cards.size() == REVIVAL_DECK.starter_cards.size(), "service creates one Card view per starter card")
	_expect(service.get_instances().size() == cards.size(), "service tracks one exact instance per Card view")
	for index in range(cards.size()):
		var card := cards[index]
		var instance := service.get_instances()[index]
		_expect(card is Card, "starter view is the new Card type")
		_expect(card.get_card_inst() == instance, "starter Card keeps the exact tracked CardInstance")
		_expect(card.get_parent() == fixture.hand_zone, "starter Card is parented to HandZone")
		_expect(card.drag_layer == fixture.drag_layer, "starter Card binds the configured DraggerLayer")
		_expect(instance.cur_zone == CardInstance.ZONE.HAND, "starter CardInstance is normalized to HAND")

	if not cards.is_empty():
		var first := cards[0]
		first.get_card_inst().current_points = 37
		first.refresh_display()
		_expect(first.attack_label.text == "37", "refresh_display updates the visible point label after instance mutation")

	await _free_fixture(fixture)


func _test_grant_and_return_use_hand_zone_without_capacity_rules() -> void:
	var fixture := _create_fixture()
	var service: RunCardService = fixture.service
	var data: CardData = REVIVAL_DECK.starter_cards[0]
	_expect(service.grant_to_hand(data), "grant_to_hand creates an acquired Card")
	_expect(service.grant_to_hand_temporarily(data), "temporary grant remains a compatibility alias without hand capacity mutation")
	var granted := service.get_card_views()[0]
	_expect(fixture.hand_zone.remove_card(granted), "fixture removes an owned Card from HandZone")
	_expect(service.return_existing_to_hand(granted, true), "return_existing_to_hand restores the exact Card to HandZone")
	_expect(fixture.hand_zone.owns_card(granted), "returned Card is owned by HandZone")
	_expect(not service.return_existing_to_hand(granted, true), "returning a Card already in HandZone is rejected")
	await _free_fixture(fixture)


func _test_forget_untracks_without_freeing() -> void:
	var fixture := _create_fixture()
	var service: RunCardService = fixture.service
	_expect(service.grant_to_hand(REVIVAL_DECK.starter_cards[0]), "fixture grants a Card before forgetting it")
	var card := service.get_card_views()[0]
	_expect(service.forget_card(card), "forget_card removes Card ownership tracking")
	_expect(service.get_card_views().is_empty() and service.get_instances().is_empty(), "forget_card removes both exact references")
	_expect(is_instance_valid(card), "forget_card leaves the Card node alive for zone-owned completion")
	card.queue_free()
	await _free_fixture(fixture)


func _create_fixture() -> Dictionary:
	var host := Node.new()
	root.add_child(host)
	var hand_zone := HAND_SCENE.instantiate() as HandZone
	var drag_layer := DRAGGER_SCENE.instantiate() as DraggerLayer
	host.add_child(hand_zone)
	host.add_child(drag_layer)
	var service := RunCardService.new()
	_expect(service.configure(CARD_SCENE, hand_zone, drag_layer), "RunCardService accepts Card/HandZone/DraggerLayer dependencies")
	return {"host": host, "hand_zone": hand_zone, "drag_layer": drag_layer, "service": service}


func _free_fixture(fixture: Dictionary) -> void:
	var service: RunCardService = fixture.service
	service.clear()
	await process_frame
	var host: Node = fixture.host
	if is_instance_valid(host):
		host.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
