extends SceneTree

const SHOP_ZONE_SCENE := preload("res://scenes/zone/shop_zone.tscn")

func _init() -> void:
	var zone := SHOP_ZONE_SCENE.instantiate() as ShopZone
	root.add_child(zone)
	await process_frame
	await process_frame
	for card in zone.get_products():
		print("CARD name=", card.name, " size=", card.size, " position=", card.position, " hit_rect=", card.get_global_rect())
	quit()
