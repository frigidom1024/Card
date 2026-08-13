class_name ReclaimZone
extends CardZone

@onready var reclaim_value_label: Label = $Content/ReclaimValue
@onready var hover_overlay: ColorRect = $HoverOverlay

var _player: PlayerData
var _card_service: RunCardService
var _pricing: MarketPricingService
var _pricing_context
var _drag_layer: DraggerLayer
var _preview_card: Card


func _ready() -> void:
	refresh_display()


func _exit_tree() -> void:
	if _drag_layer != null and is_instance_valid(_drag_layer):
		_drag_layer.unregister_zone(self)


func configure(
	player: PlayerData,
	card_service: RunCardService,
	pricing: MarketPricingService,
	pricing_context = null
) -> bool:
	if player == null or card_service == null or pricing == null:
		return false
	_player = player
	_card_service = card_service
	_pricing = pricing
	_pricing_context = pricing_context
	refresh_display()
	return true


func set_drag_layer(value: DraggerLayer) -> void:
	if _drag_layer != null and is_instance_valid(_drag_layer):
		_drag_layer.unregister_zone(self)
	_drag_layer = value
	if _drag_layer != null:
		_drag_layer.register_zone(self)


func can_reclaim(card: Card) -> bool:
	if (
		_player == null
		or _card_service == null
		or _pricing == null
		or card == null
		or not is_instance_valid(card)
		or not (card.cur_zone is HandZone)
	):
		return false

	var card_inst := card.get_card_inst()
	if card_inst == null or card_inst.card_data == null:
		return false
	if not _card_service.can_destroy_existing_instance(card_inst, card):
		return false
	return get_reclaim_price(card) > 0


func get_reclaim_price(card: Card) -> int:
	if _pricing == null or card == null or not is_instance_valid(card):
		return 0
	var card_inst := card.get_card_inst()
	if card_inst == null or card_inst.card_data == null:
		return 0
	return maxi(0, _pricing.get_reclaim_price(card_inst.card_data, _pricing_context))


func refresh_display() -> void:
	if not is_node_ready():
		return

	var preview_price := get_reclaim_price(_preview_card) if can_reclaim(_preview_card) else 0
	hover_overlay.visible = preview_price > 0
	if preview_price > 0:
		reclaim_value_label.text = "回收 +%d" % preview_price
	else:
		reclaim_value_label.text = "拖入手牌以回收"


func add_card(_card: Card, _keep_global_position: bool = true) -> bool:
	return false


func remove_card(_card: Card) -> bool:
	return false


func get_cards() -> Array[Card]:
	return []


func update_drag(card: Card) -> void:
	_preview_card = card if can_reclaim(card) else null
	refresh_display()


func can_trans_to_target(card: Card) -> bool:
	return can_reclaim(card)


func can_trans_from_source(_card: Card) -> bool:
	return false


func drag_end_source(_card: Card, _ok: bool) -> bool:
	return false


func drag_end_target(card: Card, ok: bool) -> bool:
	if not ok:
		_clear_preview()
		return false
	if not can_reclaim(card):
		_clear_preview()
		return false

	var card_inst := card.get_card_inst()
	var reclaim_price := get_reclaim_price(card)
	if reclaim_price <= 0 or not _card_service.destroy_existing_instance(card_inst, card):
		_clear_preview()
		return false

	_player.gold += reclaim_price
	_clear_preview()
	return true


func _clear_preview() -> void:
	_preview_card = null
	refresh_display()
