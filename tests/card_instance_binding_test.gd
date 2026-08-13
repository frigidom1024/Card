extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")

class TrackingDraggerLayer:
	extends DraggerLayer

	var update_count := 0
	var last_card: Card

	func update_drag(card: Card) -> void:
		update_count += 1
		last_card = card


var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var card := CARD_SCENE.instantiate() as Card
	root.add_child(card)
	await process_frame

	var attack_label := card.get_node("CardTexture/SubViewport/AttackLabel/Label") as Label
	var defense_label := card.get_node("CardTexture/SubViewport/DefenseLabel/Label") as Label
	var artwork := card.get_node("CardTexture/SubViewport/Artwork") as TextureRect

	var data := CardData.new()
	data.max_points = 7
	data.armor = 3
	data.artwork_path = "res://assert/card/ribwood_guardian_root.png"
	var card_inst := CardInstance.new(data)

	_expect(card.has_method("bind_card_inst"), "Card exposes bind_card_inst")
	_expect(card.has_method("get_card_inst"), "Card exposes get_card_inst")
	_expect(card.has_method("refresh_display"), "Card exposes refresh_display")
	if card.has_method("bind_card_inst") and card.has_method("get_card_inst"):
		card.bind_card_inst(card_inst)
		_expect(card.get_card_inst() == card_inst, "Card keeps the exact CardInstance identity")
		_expect(attack_label.text == "7", "binding updates the current-points label")
		_expect(defense_label.text == "3", "binding updates the current-armor label")
		_expect(artwork.visible, "binding shows artwork for a valid image path")
		_expect(artwork.texture != null, "binding loads the configured artwork texture")

		var replacement_data := CardData.new()
		replacement_data.max_points = 11
		replacement_data.armor = 5
		replacement_data.artwork_path = "res://assert/card/ribwood_ember_blade.png"
		var replacement_inst := CardInstance.new(replacement_data)
		card.bind_card_inst(replacement_inst)
		_expect(attack_label.text == "11", "rebinding refreshes the current-points label")
		_expect(defense_label.text == "5", "rebinding refreshes the current-armor label")
		_expect(
			artwork.texture != null
			and artwork.texture.resource_path == replacement_data.artwork_path,
			"rebinding replaces the artwork texture"
		)

		card.bind_card_inst(null)
		_expect(card.get_card_inst() == null, "binding null clears the CardInstance")
		_expect(attack_label.text == "0", "binding null clears the current-points label")
		_expect(defense_label.text == "0", "binding null clears the current-armor label")
		_expect(not artwork.visible, "binding null hides artwork")
		_expect(artwork.texture == null, "binding null clears artwork texture")

	var dragger := TrackingDraggerLayer.new()
	root.add_child(dragger)
	card.bind_drag_layer(dragger)
	card.dragging = true
	card.call("_update_drag", Vector2.ZERO)
	_expect(dragger.update_count == 1, "Card notifies DraggerLayer during drag movement")
	_expect(dragger.last_card == card, "Card passes itself to DraggerLayer.update_drag")

	card.free()
	dragger.free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
