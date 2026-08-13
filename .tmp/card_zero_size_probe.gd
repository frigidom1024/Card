extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")

func _init() -> void:
	var card := CARD_SCENE.instantiate() as Card
	print("A unattached default size=", card.size)
	card.size = Vector2.ZERO
	print("B unattached after set zero size=", card.size)
	root.add_child(card)
	print("C attached same frame size=", card.size)
	await process_frame
	print("D attached next frame size=", card.size)
	card.size = Vector2.ZERO
	print("E attached after set zero size=", card.size)
	await process_frame
	print("F attached next frame after zero size=", card.size)
	quit()
