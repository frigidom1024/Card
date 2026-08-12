extends SceneTree

const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")

var _failure_count := 0

func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var host := Node2D.new()
	root.add_child(host)
	current_scene = host

	var card := CardEntityScene.instantiate() as CardEntity
	host.add_child(card)
	await process_frame

	_expect(card.get_node_or_null("CardInteractionController") != null, "card routes pointer and drag behavior through an interaction controller")
	_expect(card.get_node_or_null("CardDisplayController") != null, "card owns a display controller for CardView updates")
	_expect(card.get_node_or_null("CardInfoController") != null, "card owns an info controller for hover notes and zoom")
	_expect(card.get_node_or_null("CardTagController") != null, "card owns a tag controller for combat stat badges")

	card.bind_instance(CardInstance.create_debug_card())
	await process_frame
	_expect(card.get_node("CardView").get("card_inst") == card.card_instance, "binding a card instance still refreshes the visual card")
	_expect(card.get_node("CombatTagAnchor/TagContainer").get_child_count() > 0, "binding a card instance still refreshes combat tags")

	card._on_mouse_entered()
	await process_frame
	await process_frame
	_expect(card.get_node_or_null("CardInfoOverlay") != null, "hover behavior still opens the card info overlay after controller extraction")
	card._on_mouse_exited()

	host.free()
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
