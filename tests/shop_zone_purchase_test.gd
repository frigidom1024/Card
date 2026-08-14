extends SceneTree

const SHOP_ZONE_SCENE := preload("res://scenes/zone/shop_zone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const HAND_ZONE_SCENE := preload("res://scenes/zone/handzone.tscn")
const TOLERANCE := 0.01

var _failures := 0
var _allow_purchase := true
var _validated_card: Card
var _validated_inst: CardInstance
var _validated_slot := -1
var _purchased_card: Card
var _purchased_inst: CardInstance
var _purchased_slot := -1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var zone := SHOP_ZONE_SCENE.instantiate() as ShopZone
	root.add_child(zone)
	await process_frame
	zone.clear_products(true)
	await process_frame

	var first := _make_card()
	var second := _make_card()
	var third := _make_card()
	zone.set_purchase_validator(_validate_purchase)
	zone.set_products([first, second, third])
	await process_frame

	_expect(zone.get_products().size() == 3, "ShopZone stores three products")
	_expect(zone.get_product(0) == first and zone.get_product(2) == third, "ShopZone preserves slot order")
	_expect(zone.get_product_slot(second) == 1, "ShopZone finds a product slot")
	_expect(zone.has_product(third), "ShopZone reports product membership")
	_expect(zone.owns_card(first) and first.get_card_inst().cur_zone == CardInstance.ZONE.SHOP and first.get_parent() == zone, "ShopZone owns stocked Cards and marks their instances SHOP")
	_expect(first.get_card_inst().battlefield_pos == Vector2i(-1, -1) and first.get_card_inst().direction == 0, "ShopZone normalizes product spatial state")
	_expect(first.position.x < second.position.x and second.position.x < third.position.x, "ShopZone lays products out from left to right")

	_expect(zone.can_trans_from_source(second), "bound affordable product can leave ShopZone")
	_expect(_validated_card == second, "purchase validator receives the Card")
	_expect(_validated_inst == second.get_card_inst(), "purchase validator receives the exact CardInstance")
	_expect(_validated_slot == 1, "purchase validator receives the stable slot")

	var unbound := CARD_SCENE.instantiate() as Card
	_expect(not zone.add_card(unbound), "ShopZone rejects an unbound product")
	unbound.free()

	zone.start_drag(second)
	_expect(zone.has_active_product_drag(), "ShopZone tracks the active product drag")
	_expect(zone.get_dragging_product() == second, "ShopZone exposes the dragging product")
	_expect(zone.get_product(1) == second, "starting a product drag keeps the stable slot")
	_expect(zone.owns_card(second), "starting a product drag keeps stable ShopZone ownership")
	_expect(zone.can_trans_from_source(second), "dragging product remains a valid source")
	var original_target := second.target_position
	second.target_position += Vector2(100.0, 50.0)
	_expect(zone.drag_end_source(second, false), "ShopZone handles a failed source drag")
	_expect(zone.get_product(1) == second, "failed purchase keeps the original slot")
	_expect(second.target_position.distance_to(original_target) <= TOLERANCE, "failed purchase restores the original anchor")
	_expect(not zone.has_active_product_drag(), "failed purchase clears drag state")

	zone.product_purchased.connect(_on_product_purchased)
	zone.start_drag(second)
	_expect(zone.get_product(1) == second, "purchase drag keeps the product in its stable slot until commit")
	_expect(zone.can_trans_from_source(second), "purchase drag remains valid during end-of-drag validation")
	var target_zone := HAND_ZONE_SCENE.instantiate() as HandZone
	root.add_child(target_zone)
	await process_frame
	_expect(zone.drag_end_source(second, true), "ShopZone commits the source before the target")
	_expect(zone.get_product_slot(second) == -1, "source commit vacates only the purchased slot")
	_expect(target_zone.add_card(second), "target HandZone commits the product after source completion")
	_expect(second.get_parent() == target_zone and target_zone.owns_card(second) and second.get_card_inst().cur_zone == CardInstance.ZONE.HAND, "ShopZone preserves the target's committed Card ownership")
	_expect(_purchased_card == second and _purchased_inst == second.get_card_inst(), "purchase signal carries exact Card and CardInstance")
	_expect(_purchased_slot == 1, "purchase signal carries the vacated slot")

	var replacement := _make_card()
	_expect(zone.replace_product(1, replacement), "ShopZone can restock a vacated slot")
	await process_frame
	_expect(zone.get_product(1) == replacement, "replacement occupies the requested slot")
	_expect(zone.owns_card(replacement) and replacement.get_card_inst().cur_zone == CardInstance.ZONE.SHOP and replacement.get_parent() == zone, "replacement becomes a ShopZone product")

	zone.clear_products(true)
	await process_frame
	if is_instance_valid(second):
		second.free()
	if is_instance_valid(target_zone):
		target_zone.free()
	zone.free()
	quit(1 if _failures > 0 else 0)


func _make_card() -> Card:
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(CardInstance.new(CardData.new()))
	return card


func _validate_purchase(card: Card, card_inst: CardInstance, slot_index: int) -> bool:
	_validated_card = card
	_validated_inst = card_inst
	_validated_slot = slot_index
	return _allow_purchase


func _on_product_purchased(card: Card, card_inst: CardInstance, slot_index: int) -> void:
	_purchased_card = card
	_purchased_inst = card_inst
	_purchased_slot = slot_index


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
