class_name PersistentMarketCoordinator
extends RefCounted

## Owns the persistent market transaction flow for a single run.
##
## DragLayer retains visual-card lifetime. This coordinator only resolves market
## rules, updates the market view, and changes run ownership after success.

const MarketPriceContextScript := preload("res://scripts/game/market/market_price_context.gd")
const PersistentMarketResolverScript := preload("res://scripts/game/market/persistent_market_resolver.gd")
const PersistentMarketStateScript := preload("res://scripts/game/market/persistent_market_state.gd")

signal player_state_changed
signal market_message_changed(text: String, is_error: bool)
signal market_ready_changed(is_ready: bool)

var _market
var _player: PlayerData
var _hand_area: HandArea
var _card_service: RunCardService
var _pricing: Object
var _state: PersistentMarketState
var _resolver: PersistentMarketResolver
var _drag_layer: DragLayer
var _ready := false


func configure(
	market,
	card_library: CardLibrary,
	player: PlayerData,
	hand_area: HandArea,
	card_service: RunCardService,
	pricing: Object,
	rng: RandomNumberGenerator,
	progression: RunProgressionService = null
) -> bool:
	if market == null or card_library == null or player == null or hand_area == null or card_service == null or pricing == null or rng == null:
		_set_ready(false)
		return false
	_market = market
	_player = player
	_hand_area = hand_area
	_card_service = card_service
	_pricing = pricing
	_state = PersistentMarketStateScript.new()
	_state.initialize(card_library, rng, progression)
	_resolver = PersistentMarketResolverScript.new(_pricing)
	_market.configure(_state, _player, _pricing)
	_set_ready(true)
	return true


func connect_drag_layer(drag_layer: DragLayer, hand_tray: HandTray) -> void:
	_drag_layer = drag_layer
	if _drag_layer == null or hand_tray == null:
		return
	_drag_layer.set_market_context(_market, hand_tray)
	if not _drag_layer.market_purchase_requested.is_connected(handle_purchase_requested):
		_drag_layer.market_purchase_requested.connect(handle_purchase_requested)
	if not _drag_layer.market_reclaim_requested.is_connected(handle_reclaim_requested):
		_drag_layer.market_reclaim_requested.connect(handle_reclaim_requested)
	if _market != null and not _market.refresh_requested.is_connected(handle_refresh_requested):
		_market.refresh_requested.connect(handle_refresh_requested)


func handle_purchase_requested(card: CardEntity, slot_index: int) -> void:
	if not _ready or card == null or not is_instance_valid(card):
		return
	var result := _resolver.purchase(_state, slot_index, _player, not _hand_area.is_full(), create_price_context())
	if not result.success:
		_show_message(_failure_message(result.failure), true)
		return
	_market.restore_offer_card(card, slot_index)
	_market.refresh_display()
	if not _card_service.grant_to_hand(result.card_data):
		_show_message("CARD COULD NOT BE ADDED", true)
		return
	player_state_changed.emit()
	_show_message("CARD PURCHASED", false)


func handle_reclaim_requested(card: CardEntity) -> void:
	if not _ready or card == null or not is_instance_valid(card):
		return
	if card not in _card_service.get_entities() or card.card_instance == null:
		return
	var result := _resolver.reclaim(card.card_instance.card_data, _player, create_price_context())
	if not result.success:
		_show_message(_failure_message(result.failure), true)
		return
	if not _card_service.forget_card(card):
		return
	if _drag_layer != null:
		_drag_layer.confirm_market_reclaim(card)
	player_state_changed.emit()
	_show_message("CARD RECLAIMED · +%d GOLD" % result.gold_delta, false)


func handle_refresh_requested() -> void:
	if not _ready:
		return
	var result := _resolver.refresh(_state, _player, create_price_context())
	if not result.success:
		_show_message(_failure_message(result.failure), true)
		return
	_market.refresh_display()
	player_state_changed.emit()
	_show_message("MARKET REFRESHED", false)


func create_price_context():
	var context = MarketPriceContextScript.new()
	context.player = _player
	context.market_state = _state
	return context


func get_state() -> PersistentMarketState:
	return _state


func is_ready() -> bool:
	return _ready


func _show_message(text: String, is_error: bool) -> void:
	if _market != null:
		_market.show_message(text, is_error)
	market_message_changed.emit(text, is_error)


func _failure_message(failure: int) -> String:
	match failure:
		PersistentMarketResolver.Failure.HAND_FULL:
			return "HAND FULL"
		PersistentMarketResolver.Failure.INSUFFICIENT_GOLD:
			return "NOT ENOUGH GOLD"
		PersistentMarketResolver.Failure.INVALID_CARD, PersistentMarketResolver.Failure.INVALID_OFFER:
			return "TRANSACTION FAILED"
		_:
			return "TRANSACTION FAILED"


func _set_ready(next_ready: bool) -> void:
	if _ready == next_ready:
		return
	_ready = next_ready
	market_ready_changed.emit(_ready)
