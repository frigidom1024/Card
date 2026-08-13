extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")
const SHOP_ZONE_SCENE := preload("res://scenes/zone/shop_zone.tscn")

func _fail(message: String) -> void:
	push_error(message)
	print("shop_zone_layout_test: FAIL - ", message)
	quit(1)

func _assert_vector2_approx(actual: Vector2, expected: Vector2, message: String) -> bool:
	if not is_equal_approx(actual.x, expected.x) or not is_equal_approx(actual.y, expected.y):
		_fail("%s (actual=%s, expected=%s)" % [message, actual, expected])
		return false
	return true

func _init() -> void:
	var zone := SHOP_ZONE_SCENE.instantiate() as ShopZone
	root.add_child(zone)
	await process_frame
	await process_frame

	if zone.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("ShopZone must not intercept card GUI input")
		return

	var products := zone.get_products()
	if products.size() != 3:
		_fail("ShopZone must expose its three default product cards")
		return
	for card in products:
		if not _assert_vector2_approx(card.size, Vector2(84.0, 154.0), "ShopZone must preserve the Card scene's original size"):
			return
		if card.get_global_rect().size.x <= 0.0:
			_fail("Each product card must have a positive GUI hit width")
			return
	var first := products[0]
	var middle := products[1]
	var last := products[2]
	if first.position.x >= middle.position.x or middle.position.x >= last.position.x:
		_fail("Products must be left-to-right")
		return

	zone.size = Vector2(300.0, 200.0)
	await process_frame
	await process_frame
	var group_left: float = first.position.x
	var group_right: float = last.position.x + last.size.x
	if not is_equal_approx((group_left + group_right) * 0.5, zone.size.x * 0.5):
		_fail("Products must remain horizontally centered after resize")
		return
	for card in products:
		if not _assert_vector2_approx(card.size, Vector2(84.0, 154.0), "Resizing ShopZone must not resize product cards"):
			return

	var fallback_card := CARD_SCENE.instantiate() as Card
	zone.add_child(fallback_card)
	fallback_card.size = Vector2.ZERO
	zone.set_products([fallback_card])
	await process_frame
	await process_frame
	if not _assert_vector2_approx(fallback_card.size, Vector2.ZERO, "Fallback layout must not overwrite a zero-sized Card"):
		return
	if not _assert_vector2_approx(fallback_card.position, Vector2((zone.size.x - zone.fallback_card_size.x) * 0.5, (zone.size.y - zone.fallback_card_size.y) * 0.5), "Fallback size must determine zero-sized Card layout"):
		return

	var replacement_card := CARD_SCENE.instantiate() as Card
	zone.set_product(0, replacement_card)
	await process_frame
	await process_frame
	var replacement_products := zone.get_products()
	if replacement_products.size() != 1 or replacement_products[0] != replacement_card:
		_fail("set_product must replace the requested display slot")
		return
	if replacement_card.get_parent() != zone or not replacement_card.visible:
		_fail("set_product must add an unattached product card to ShopZone")
		return

	zone.clear_products()
	if not zone.get_products().is_empty() or replacement_card.visible:
		_fail("clear_products must hide and remove all displayed products")
		return

	print("shop_zone_layout_test: PASS")
	quit()

