extends SceneTree

func _init() -> void:
	var shop_zone_scene := load("res://scenes/zone/shop_zone.tscn") as PackedScene
	var shop_zone := shop_zone_scene.instantiate() as Control
	root.add_child(shop_zone)
	await process_frame
	print("SHOP_ZONE size=", shop_zone.size, " rect=", shop_zone.get_global_rect(), " mouse_filter=", shop_zone.mouse_filter)
	var container := shop_zone.get_node("HBoxContainer") as HBoxContainer
	print("CONTAINER size=", container.size, " rect=", container.get_global_rect(), " min=", container.get_combined_minimum_size(), " mouse_filter=", container.mouse_filter)
	for child in container.get_children():
		if child is Control:
			var card := child as Control
			print("CARD name=", card.name, " visible=", card.visible, " size=", card.size, " rect=", card.get_global_rect(), " min=", card.get_combined_minimum_size(), " mouse_filter=", card.mouse_filter, " disabled=", (card as BaseButton).disabled)
	quit()
