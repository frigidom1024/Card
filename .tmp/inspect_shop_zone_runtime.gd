extends SceneTree

const SHOP_ZONE_SCENE := preload("res://scenes/zone/shop_zone.tscn")

func _init() -> void:
	var zone := SHOP_ZONE_SCENE.instantiate() as ShopZone
	root.add_child(zone)
	await process_frame
	await process_frame
	print("ZONE size=", zone.size, " rect=", zone.get_global_rect(), " mouse=", zone.mouse_filter)
	for card in zone.get_products():
		print("CARD ", card.name, " size=", card.size, " min=", card.get_combined_minimum_size(), " position=", card.position, " rect=", card.get_global_rect(), " anchors=", card.anchor_left, ",", card.anchor_top, ",", card.anchor_right, ",", card.anchor_bottom)
	quit()
