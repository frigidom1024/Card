extends SceneTree

const CardEntityScene := preload("res://scenes/card_view/card_entity.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_expect(CardData.CardType.GUIDE != CardData.CardType.NORMAL, "GUIDE must be a distinct CardType")
	var guide := _make_card(CardData.CardType.GUIDE)
	_expect(guide.card_instance.card_data.card_type == CardData.CardType.GUIDE, "guide card keeps GUIDE type")
	guide.queue_free()
	quit(1 if _failure_count > 0 else 0)


func _make_card(card_type: CardData.CardType) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	var data := CardData.new()
	data.card_type = card_type
	data.card_name = "Test Card"
	card.bind_instance(CardInstance.new(data))
	root.add_child(card)
	return card


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
