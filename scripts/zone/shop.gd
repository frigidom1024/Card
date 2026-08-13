class_name Shop
extends Panel

const CARD_SCENE := preload("res://scenes/card/card.tscn")

@onready var refresh_button: Button = \
	$MarginContainer/VBoxContainer/HBoxContainer/RefreshButton
@onready var cost_coin_label: Label = \
	$MarginContainer/VBoxContainer/HBoxContainer/CostCoin
@onready var shop_zone: ShopZone = \
	$MarginContainer/VBoxContainer/ShopZone

var _card_library: CardLibrary
var _player: PlayerData
var _card_service: RunCardService
var _pricing: MarketPricingService
var _rng: RandomNumberGenerator
var _progression: RunProgressionService
var _drag_layer: DraggerLayer
var _offers: Array[CardInstance] = []

var _validated_card: Card
var _validated_card_inst: CardInstance
var _validated_slot := -1
var _validated_price := 0


func _ready() -> void:
	_connect_internal_callbacks()
	refresh_display()


func _process(_delta: float) -> void:
	_update_refresh_button_state()


func _exit_tree() -> void:
	if _drag_layer != null and is_instance_valid(shop_zone):
		_drag_layer.unregister_zone(shop_zone)


func configure(
	card_library: CardLibrary,
	player: PlayerData,
	card_service: RunCardService,
	pricing: MarketPricingService,
	rng: RandomNumberGenerator,
	progression: RunProgressionService = null
) -> bool:
	if (
		card_library == null
		or player == null
		or card_service == null
		or pricing == null
		or rng == null
		or not is_instance_valid(shop_zone)
		or shop_zone.has_active_product_drag()
	):
		return false

	_card_library = card_library
	_player = player
	_card_service = card_service
	_pricing = pricing
	_rng = rng
	_progression = progression
	_clear_purchase_validation()
	_connect_internal_callbacks()

	var initial_offers := _build_offer_set()
	var product_cards := _create_product_cards(initial_offers)
	shop_zone.clear_products(true)
	_offers = initial_offers
	shop_zone.set_products(product_cards)
	_bind_product_cards_to_drag_layer()
	refresh_display()
	return true


func set_drag_layer(value: DraggerLayer) -> void:
	if _drag_layer != null:
		_drag_layer.unregister_zone(shop_zone)
	_drag_layer = value
	if _drag_layer != null:
		_drag_layer.register_zone(shop_zone)
	_bind_product_cards_to_drag_layer()
	refresh_display()


func refresh_shop() -> bool:
	if not _is_configured() or shop_zone.has_active_product_drag():
		refresh_display()
		return false

	var refresh_cost := _get_refresh_cost()
	if _player.gold < refresh_cost:
		refresh_display()
		return false

	var refreshed_offers := _build_offer_set()
	if not _contains_offer(refreshed_offers):
		refresh_display()
		return false
	var refreshed_cards := _create_product_cards(refreshed_offers)
	if refreshed_cards.is_empty():
		refresh_display()
		return false

	_player.gold -= refresh_cost
	_clear_purchase_validation()
	shop_zone.clear_products(true)
	_offers = refreshed_offers
	shop_zone.set_products(refreshed_cards)
	_bind_product_cards_to_drag_layer()
	refresh_display()
	return true


func refresh_display() -> void:
	if is_instance_valid(cost_coin_label):
		cost_coin_label.text = str(_get_refresh_cost()) if _is_configured() else "0"
	_update_refresh_button_state()


func get_offer(slot_index: int) -> CardInstance:
	if slot_index < 0 or slot_index >= _offers.size():
		return null
	return _offers[slot_index]


func get_offers() -> Array[CardInstance]:
	return _offers.duplicate()


func get_offer_data(slot_index: int) -> CardData:
	var offer := get_offer(slot_index)
	return offer.card_data if offer != null else null


func get_offer_slot_for_card(card: Card) -> int:
	if card == null or not is_instance_valid(shop_zone):
		return -1
	var slot_index := shop_zone.get_product_slot(card)
	if slot_index < 0 or get_offer(slot_index) != card.get_card_inst():
		return -1
	return slot_index


func _connect_internal_callbacks() -> void:
	if is_instance_valid(refresh_button) and not refresh_button.pressed.is_connected(
		_on_refresh_button_pressed
	):
		refresh_button.pressed.connect(_on_refresh_button_pressed)
	if is_instance_valid(shop_zone):
		shop_zone.set_purchase_validator(_can_purchase_product)
		if not shop_zone.product_purchased.is_connected(_on_product_purchased):
			shop_zone.product_purchased.connect(_on_product_purchased)


func _on_refresh_button_pressed() -> void:
	refresh_shop()


func _can_purchase_product(
	card: Card,
	card_inst: CardInstance,
	slot_index: int
) -> bool:
	_clear_purchase_validation()
	if (
		not _is_configured()
		or slot_index < 0
		or slot_index >= _offers.size()
		or _offers[slot_index] != card_inst
		or shop_zone.get_product(slot_index) != card
		or card == null
		or card.get_card_inst() != card_inst
		or card_inst == null
		or card_inst.card_data == null
		or not _card_service.can_register_existing_instance(card_inst, card)
	):
		return false

	var purchase_price := _pricing.get_purchase_price(card_inst.card_data, _make_price_context())
	if _player.gold < purchase_price:
		return false

	_validated_card = card
	_validated_card_inst = card_inst
	_validated_slot = slot_index
	_validated_price = purchase_price
	return true


func _on_product_purchased(
	card: Card,
	card_inst: CardInstance,
	slot_index: int
) -> void:
	if (
		not _is_configured()
		or slot_index < 0
		or slot_index >= _offers.size()
		or _offers[slot_index] != card_inst
		or card == null
		or card.get_card_inst() != card_inst
	):
		_clear_purchase_validation()
		refresh_display()
		return

	var purchase_price := _validated_price
	if (
		_validated_card != card
		or _validated_card_inst != card_inst
		or _validated_slot != slot_index
	):
		purchase_price = _pricing.get_purchase_price(card_inst.card_data, _make_price_context())
	if _player.gold < purchase_price:
		_clear_purchase_validation()
		refresh_display()
		return
	if not _card_service.register_existing_instance(card_inst, card):
		_clear_purchase_validation()
		refresh_display()
		return

	_player.gold -= purchase_price
	var replacement_inst := _create_replacement_offer(slot_index)
	_offers[slot_index] = replacement_inst
	if replacement_inst != null:
		var replacement_card := _create_product_card(replacement_inst)
		if replacement_card != null and shop_zone.replace_product(slot_index, replacement_card):
			replacement_card.bind_drag_layer(_drag_layer)
		else:
			_offers[slot_index] = null
			if is_instance_valid(replacement_card):
				replacement_card.queue_free()

	_clear_purchase_validation()
	refresh_display()


func _build_offer_set() -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	var selected_data: Array[CardData] = []
	for _slot_index in range(shop_zone.max_products):
		var card_data := _draw_card_data(selected_data)
		if card_data == null:
			result.append(null)
			continue
		result.append(CardInstance.new(card_data))
		selected_data.append(card_data)
	return result


func _create_replacement_offer(slot_index: int) -> CardInstance:
	var excluded: Array[CardData] = []
	for index in range(_offers.size()):
		if index == slot_index:
			continue
		var offer := _offers[index]
		if offer != null and offer.card_data != null:
			excluded.append(offer.card_data)
	var card_data := _draw_card_data(excluded)
	return CardInstance.new(card_data) if card_data != null else null


func _draw_card_data(excluded: Array[CardData]) -> CardData:
	var candidates := _get_weighted_candidates(excluded)
	if candidates.is_empty() and not excluded.is_empty():
		candidates = _get_weighted_candidates([])
	if candidates.is_empty():
		return null

	var total_weight := 0
	for candidate in candidates:
		total_weight += int(candidate.weight)
	if total_weight <= 0:
		return null
	var roll := _rng.randi_range(1, total_weight)
	var cumulative := 0
	for candidate in candidates:
		cumulative += int(candidate.weight)
		if roll <= cumulative:
			return candidate.card_data as CardData
	return candidates.back().card_data as CardData


func _get_weighted_candidates(excluded: Array[CardData]) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for card_data in _card_library.cards:
		if (
			card_data == null
			or card_data.card_type == CardData.CardType.ROOT
			or card_data in excluded
		):
			continue
		var weight := _progression.get_card_rarity_weight(card_data) \
			if _progression != null else 1
		if weight <= 0:
			continue
		candidates.append({"card_data": card_data, "weight": weight})
	return candidates


func _create_product_cards(offers: Array[CardInstance]) -> Array[Card]:
	var cards: Array[Card] = []
	for offer in offers:
		if offer == null:
			continue
		var card := _create_product_card(offer)
		if card != null:
			cards.append(card)
	return cards


func _create_product_card(card_inst: CardInstance) -> Card:
	if card_inst == null:
		return null
	var card := CARD_SCENE.instantiate() as Card
	if card == null:
		return null
	card.bind_card_inst(card_inst)
	card.bind_drag_layer(_drag_layer)
	return card


func _bind_product_cards_to_drag_layer() -> void:
	if not is_instance_valid(shop_zone):
		return
	for card in shop_zone.get_cards():
		card.bind_drag_layer(_drag_layer)


func _make_price_context() -> MarketPriceContext:
	var context := MarketPriceContext.new()
	context.player = _player
	context.market_state = self
	return context


func _get_refresh_cost() -> int:
	if not _is_configured():
		return 0
	return maxi(0, _pricing.get_refresh_cost(_make_price_context()))


func _update_refresh_button_state() -> void:
	if not is_instance_valid(refresh_button):
		return
	refresh_button.disabled = (
		not _is_configured()
		or shop_zone.has_active_product_drag()
		or _player.gold < _get_refresh_cost()
	)


func _contains_offer(offers: Array[CardInstance]) -> bool:
	for offer in offers:
		if offer != null:
			return true
	return false


func _clear_purchase_validation() -> void:
	_validated_card = null
	_validated_card_inst = null
	_validated_slot = -1
	_validated_price = 0


func _is_configured() -> bool:
	return (
		_card_library != null
		and _player != null
		and _card_service != null
		and _pricing != null
		and _rng != null
		and is_instance_valid(shop_zone)
	)
