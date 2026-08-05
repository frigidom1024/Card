class_name ShopEventView
extends Control

const MarketPriceContextScript = preload("res://scripts/game/market/market_price_context.gd")
const MarketPricingServiceScript = preload("res://scripts/game/market/market_pricing_service.gd")

signal purchase_requested(item_index: int)
signal close_requested()

var _instance: EventInstance
var _player: PlayerData
var _pricing: Object


func _ready() -> void:
	for item_index in range(3):
		var button := _action_button(item_index)
		if button != null and not button.pressed.is_connected(_on_purchase_pressed.bind(item_index)):
			button.pressed.connect(_on_purchase_pressed.bind(item_index))
		var preview := _card_preview(item_index)
		if preview != null:
			preview.set_display_only(true, true, true)
	var close_button := find_child("CloseButton", true, false) as Button
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)


func set_pricing_service(pricing: Object) -> void:
	_pricing = pricing
	_refresh()


func show_event(instance: EventInstance, player: PlayerData) -> void:
	_instance = instance
	_player = player
	_refresh()
	show()


func hide_event() -> void:
	hide()
	_instance = null
	_player = null


func show_message(message: String, is_error: bool = false) -> void:
	var hint_label := find_child("HintLabel", true, false) as Label
	if hint_label == null:
		return
	hint_label.text = message
	hint_label.modulate = Color(1.0, 0.48, 0.42) if is_error else Color.WHITE


func refresh() -> void:
	_refresh()


func _refresh() -> void:
	var gold_label := find_child("GoldLabel", true, false) as Label
	if gold_label != null:
		gold_label.text = "GOLD  %d" % (_player.gold if _player != null else 0)

	var content := _instance.get_content() as ShopEventContent if _instance != null else null
	var state := _instance.runtime_state as ShopRuntimeState if _instance != null else null
	for item_index in range(3):
		var slot := _offer_slot(item_index)
		if slot == null:
			continue
		var item: ShopItemData = content.items[item_index] if content != null and item_index < content.items.size() else null
		slot.visible = item != null and item.card_data != null
		if item == null or item.card_data == null:
			continue

		var preview := _card_preview(item_index)
		if preview != null:
			preview.bind_instance(CardInstance.new(item.card_data))
			preview.set_display_only(true, true, true)
		var price_label := slot.find_child("PriceOrRewardLabel", true, false) as Label
		if price_label != null:
			price_label.text = "%d  GOLD" % _get_purchase_price(item.card_data)
		var button := slot.find_child("ActionButton", true, false) as Button
		if button != null:
			var sold := state != null and item_index < state.sold_flags.size() and state.sold_flags[item_index]
			button.disabled = sold
			button.text = "SOLD OUT" if sold else "BUY"

	show_message("Choose one supply for the road ahead.", false)


func _offer_slot(item_index: int) -> Control:
	return find_child("OfferSlot%d" % (item_index + 1), true, false) as Control


func _action_button(item_index: int) -> Button:
	var slot := _offer_slot(item_index)
	return slot.find_child("ActionButton", true, false) as Button if slot != null else null


func _card_preview(item_index: int) -> CardEntity:
	var slot := _offer_slot(item_index)
	return slot.find_child("CardPreview", true, false) as CardEntity if slot != null else null


func _on_purchase_pressed(item_index: int) -> void:
	purchase_requested.emit(item_index)


func _on_close_pressed() -> void:
	close_requested.emit()


func _get_purchase_price(card_data: CardData) -> int:
	var pricing := _pricing if _pricing != null else MarketPricingServiceScript.new()
	return int(pricing.call("get_purchase_price", card_data, _build_price_context()))


func _build_price_context():
	var context = MarketPriceContextScript.new()
	context.player = _player
	return context
