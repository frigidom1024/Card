extends SceneTree

func _init() -> void:
	var shop_scene := load("res://scenes/zone/shop.tscn") as PackedScene
	var shop := shop_scene.instantiate() as Control
	root.add_child(shop)
	await process_frame
	var card := shop.get_node("MarginContainer/VBoxContainer/ShopZone/HBoxContainer/Card3") as Button
	print("BEFORE: card_size=", card.size, ", global_rect=", card.get_global_rect(), ", min=", card.get_combined_minimum_size())
	card.custom_minimum_size = Vector2(84.0, 154.0)
	await process_frame
	print("AFTER:  card_size=", card.size, ", global_rect=", card.get_global_rect(), ", min=", card.get_combined_minimum_size())
	quit()
