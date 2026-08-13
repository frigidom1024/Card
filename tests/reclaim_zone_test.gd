extends SceneTree

const RECLAIM_ZONE_SCENE_PATH := "res://scenes/zone/reclaim_zone.tscn"
const HAND_ZONE_SCENE := preload("res://scenes/zone/handzone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(ResourceLoader.exists(RECLAIM_ZONE_SCENE_PATH), "ReclaimZone scene exists")
	if not ResourceLoader.exists(RECLAIM_ZONE_SCENE_PATH):
		quit(1)
		return

	var reclaim_scene := load(RECLAIM_ZONE_SCENE_PATH) as PackedScene
	var reclaim_zone := reclaim_scene.instantiate() as CardZone
	var hand_zone := HAND_ZONE_SCENE.instantiate() as HandZone
	var drag_layer := DraggerLayer.new()
	root.add_child(hand_zone)
	root.add_child(reclaim_zone)
	root.add_child(drag_layer)
	await process_frame

	var player := PlayerData.new()
	player.gold = 7
	var card_service := RunCardService.new()
	var pricing := MarketPricingService.new()
	_expect(reclaim_zone.call("configure", player, card_service, pricing), "ReclaimZone accepts required dependencies")
	_expect(not reclaim_zone.call("configure", null, card_service, pricing), "ReclaimZone rejects missing dependencies")
	_expect(reclaim_zone.call("configure", player, card_service, pricing), "ReclaimZone can be restored after invalid configuration attempt")

	reclaim_zone.call("set_drag_layer", drag_layer)
	_expect(drag_layer.get_registered_zones().has(reclaim_zone), "ReclaimZone registers itself with the current drag layer")
	var replacement_layer := DraggerLayer.new()
	root.add_child(replacement_layer)
	reclaim_zone.call("set_drag_layer", replacement_layer)
	_expect(not drag_layer.get_registered_zones().has(reclaim_zone), "ReclaimZone unregisters from the previous drag layer")
	_expect(replacement_layer.get_registered_zones().has(reclaim_zone), "ReclaimZone registers with the replacement drag layer")

	var card_data := CardData.new()
	card_data.rarity = CardData.Rarity.COMMON
	var card_inst := CardInstance.new(card_data)
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(card_inst)
	root.add_child(card)
	await process_frame
	_expect(card_service.register_existing_instance(card_inst, card), "fixture registers the owned Card pair")
	_expect(hand_zone.add_card(card), "fixture places the owned Card in hand")
	_expect(reclaim_zone.call("can_reclaim", card), "ReclaimZone accepts an owned HandZone Card")
	_expect(reclaim_zone.call("get_reclaim_price", card) == 1, "ReclaimZone uses the minimum reclaim price")

	reclaim_zone.update_drag(card)
	var value_label := reclaim_zone.get_node_or_null("Content/ReclaimValue") as Label
	_expect(value_label != null and value_label.text.contains("1"), "drag preview shows the reclaim value")
	var gold_before_cancel := player.gold
	_expect(not reclaim_zone.drag_end_target(card, false), "cancelled reclaim does not commit")
	_expect(player.gold == gold_before_cancel, "cancelled reclaim does not add gold")
	_expect(card_service.get_instances().has(card_inst), "cancelled reclaim keeps CardInstance ownership")
	_expect(hand_zone.get_cards().has(card), "cancelled reclaim keeps the Card in hand")

	var shop_card := CARD_SCENE.instantiate() as Card
	var shop_inst := CardInstance.new(CardData.new())
	shop_card.bind_card_inst(shop_inst)
	var shop_zone := ShopZone.new()
	root.add_child(shop_zone)
	root.add_child(shop_card)
	shop_card.cur_zone = shop_zone
	_expect(not reclaim_zone.call("can_reclaim", shop_card), "ReclaimZone rejects ShopZone products")
	shop_card.free()
	shop_zone.free()

	hand_zone.start_drag(card)
	reclaim_zone.update_drag(card)
	var gold_before_reclaim := player.gold
	_expect(reclaim_zone.drag_end_target(card, true), "valid reclaim commits in the target zone")
	_expect(hand_zone.drag_end_source(card, true), "HandZone clears its source reference after commit")
	_expect(player.gold == gold_before_reclaim + 1, "successful reclaim adds the exact reclaim price")
	_expect(not card_service.get_instances().has(card_inst), "successful reclaim removes the exact CardInstance")
	_expect(not card_service.get_card_views().has(card), "successful reclaim removes the exact Card view")
	_expect(card_inst.cur_zone == CardInstance.ZONE.DISCARD, "successful reclaim marks the instance discarded")
	_expect(not hand_zone.get_cards().has(card), "successful reclaim removes the Card from HandZone")
	await process_frame
	_expect(not is_instance_valid(card), "successful reclaim frees the Card view")

	reclaim_zone.call("set_drag_layer", null)
	_expect(not replacement_layer.get_registered_zones().has(reclaim_zone), "clearing drag layer unregisters ReclaimZone")
	hand_zone.free()
	reclaim_zone.free()
	drag_layer.free()
	replacement_layer.free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
