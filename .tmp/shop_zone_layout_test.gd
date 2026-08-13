extends SceneTree

const SHOP_ZONE_SCENE := preload("res://scenes/zone/shop_zone.tscn")

func _fail(message: String) -> void:
	push_error(message)
	print("shop_zone_layout_test: FAIL - ", message)
	quit(1)

func _init() -> void:
	var zone := SHOP_ZONE_SCENE.instantiate() as Control
	root.add_child(zone)
	await process_frame
	await process_frame

	if zone.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("ShopZone must not intercept card GUI input")
		return
	if not zone.has_method("get_products"):
		_fail("ShopZone must expose get_products()")
		return

	var products: Array = zone.get_products()
	if products.size() != 3:
		_fail("ShopZone must expose its three default product cards")
		return
	for product in products:
		var card := product as Card
		if card == null or card.size != Vector2(84.0, 154.0):
			_fail("ShopZone must preserve the Card scene's original size")
			return
		if card.get_global_rect().size.x <= 0.0:
			_fail("Each product card must have a positive GUI hit width")
			return
	var first := products[0] as Card
	var middle := products[1] as Card
	var last := products[2] as Card
	if first.position.x >= middle.position.x or middle.position.x >= last.position.x:
		_fail("Products must be left-to-right")
		return

	zone.size = Vector2(300.0, 200.0)
	await process_frame
	var group_left: float = first.position.x
	var group_right: float = last.position.x + last.size.x
	if not is_equal_approx((group_left + group_right) * 0.5, zone.size.x * 0.5):
		_fail("Products must remain horizontally centered after resize")
		return
	for product in products:
		var card := product as Card
		if card.size != Vector2(84.0, 154.0):
			_fail("Resizing ShopZone must not resize product cards")
			return

	print("shop_zone_layout_test: PASS")
	quit()
