class_name TreasureEventView
extends Control

signal reward_requested(option_index: int)
signal close_requested()

var _options: Array[TreasureRewardOption] = []


func _ready() -> void:
	for option_index in range(3):
		var button := _action_button(option_index)
		if button != null and not button.pressed.is_connected(_on_reward_pressed.bind(option_index)):
			button.pressed.connect(_on_reward_pressed.bind(option_index))
	var close_button := find_child("CloseButton", true, false) as Button
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)


func show_event(instance: EventInstance, options: Array[TreasureRewardOption]) -> void:
	_options = options
	_refresh()
	show()


func hide_event() -> void:
	hide()
	_options.clear()


func show_message(message: String, is_error: bool = false) -> void:
	var hint_label := find_child("HintLabel", true, false) as Label
	if hint_label == null:
		return
	hint_label.text = message
	hint_label.modulate = Color(1.0, 0.48, 0.42) if is_error else Color.WHITE


func _refresh() -> void:
	for option_index in range(3):
		var slot := _offer_slot(option_index)
		if slot == null:
			continue
		var option: TreasureRewardOption = _options[option_index] if option_index < _options.size() else null
		slot.visible = option != null
		if option == null:
			continue

		var card_preview := slot.find_child("CardPreview", true, false)
		var gold_preview := slot.find_child("GoldRewardPreview", true, false) as Control
		var detail_label := slot.find_child("PriceOrRewardLabel", true, false) as Label
		var button := slot.find_child("ActionButton", true, false) as Button
		if button != null:
			button.disabled = false
			button.text = "领取"
		if option.kind == TreasureRewardOption.Kind.CARD:
			if card_preview != null:
				card_preview.visible = true
				card_preview.set_value(CardInstance.new(option.card_data))
			if gold_preview != null:
				gold_preview.visible = false
			if detail_label != null:
				detail_label.text = "卡牌奖励"
		else:
			if card_preview != null:
				card_preview.visible = false
			if gold_preview != null:
				gold_preview.visible = true
				var amount_label := gold_preview.find_child("AmountLabel", true, false) as Label
				if amount_label != null:
					amount_label.text = "+%d 金币" % option.gold_amount
			if detail_label != null:
				detail_label.text = "金币奖励"

	show_message("只能带走一项奖励。", false)


func _offer_slot(option_index: int) -> Control:
	return find_child("OfferSlot%d" % (option_index + 1), true, false) as Control


func _action_button(option_index: int) -> Button:
	var slot := _offer_slot(option_index)
	return slot.find_child("ActionButton", true, false) as Button if slot != null else null


func _on_reward_pressed(option_index: int) -> void:
	reward_requested.emit(option_index)


func _on_close_pressed() -> void:
	close_requested.emit()