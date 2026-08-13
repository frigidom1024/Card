class_name RunCardService
extends RefCounted

## Owns the cards a player has acquired during the current run.
##
## This service creates runtime CardInstance/CardEntity pairs and moves owned cards
## back to the hand. It deliberately does not know why a card is granted, sold,
## or returned: events, markets, the board, and exploration remain its callers.

var card_manager: Node2D
var hand_area: HandArea
var drag_layer: Node2D

var _instances: Array[CardInstance] = []
var _entities: Array[CardEntity] = []
var _card_views: Array[Card] = []


func configure(
	next_card_manager: Node2D, next_hand_area: HandArea, next_drag_layer: Node2D
) -> bool:
	if next_card_manager == null or next_hand_area == null or next_drag_layer == null:
		return false
	card_manager = next_card_manager
	hand_area = next_hand_area
	drag_layer = next_drag_layer
	return true


func initialize_starting_deck(starting_deck: StartingDeckData) -> bool:
	if not _is_configured() or starting_deck == null or not starting_deck.validate().is_empty():
		return false
	clear()

	var starter_instances: Array[CardInstance] = card_manager.create_starting_instances(
		starting_deck
	)
	if starter_instances.size() != starting_deck.starter_cards.size():
		return false
	for instance in starter_instances:
		if not _add_new_instance_to_hand(instance):
			clear()
			return false
	return true


func grant_to_hand(card_data: CardData) -> bool:
	if not _is_configured() or card_data == null or hand_area.is_full():
		return false
	var instance := CardInstance.new(card_data)
	instance.cur_zone = CardInstance.ZONE.HAND
	return _add_new_instance_to_hand(instance)


## Grants a newly earned card without permanently changing the normal hand limit.
## Encounter drops use this so a full hand never destroys an already won reward.
func grant_to_hand_temporarily(card_data: CardData) -> bool:
	if not _is_configured() or card_data == null:
		return false
	var previous_max_hand_size := hand_area.max_hand_size
	var used_temporary_overflow := hand_area.is_full()
	if used_temporary_overflow:
		hand_area.max_hand_size = hand_area.cards.size() + 1
	var granted := grant_to_hand(card_data)
	if used_temporary_overflow:
		hand_area.max_hand_size = previous_max_hand_size
		hand_area.hand_count_changed.emit(hand_area.cards.size(), hand_area.max_hand_size)
	return granted


## Adds an already existing card to hand. GUIDE cards use allow_overflow so they
## cannot be lost solely because the hand reached its normal size limit.
func return_existing_to_hand(card: CardEntity, allow_overflow := false) -> bool:
	if (
		not _is_configured()
		or card == null
		or not is_instance_valid(card)
		or card in hand_area.cards
	):
		return false
	if hand_area.is_full():
		if not allow_overflow:
			return false
		hand_area.max_hand_size = hand_area.cards.size() + 1
	if not hand_area.add_card(card):
		return false
	if card.card_instance != null:
		card.card_instance.cur_zone = CardInstance.ZONE.HAND
	return true


## Returns a combat RETREAT tail without permanently changing the normal hand limit.
func return_existing_to_hand_temporarily(card: CardEntity) -> bool:
	if not _is_configured():
		return false
	var previous_max_hand_size := hand_area.max_hand_size
	var used_temporary_overflow := hand_area.is_full()
	var returned := return_existing_to_hand(card, true)
	if used_temporary_overflow:
		hand_area.max_hand_size = previous_max_hand_size
		hand_area.hand_count_changed.emit(hand_area.cards.size(), hand_area.max_hand_size)
	return returned


## Stops tracking a sold card. The drag interaction owns its eventual queue_free.
func forget_card(card: CardEntity) -> bool:
	if card == null or card not in _entities:
		return false
	_entities.erase(card)
	if card.card_instance != null:
		_instances.erase(card.card_instance)
	return true


## Permanently removes an owned card after its combat points are exhausted.
## Callers remove it from the board first; this method also tolerates a card
## still being in hand so it can be reused by other discard effects.
func destroy_existing_card(card: CardEntity) -> bool:
	if card == null or card not in _entities:
		return false
	if hand_area != null and card in hand_area.cards:
		hand_area.remove_card(card, false)
	if not forget_card(card):
		return false
	if card.card_instance != null:
		card.card_instance.cur_zone = CardInstance.ZONE.DISCARD
	if is_instance_valid(card):
		card.queue_free()
	return true


func clear() -> void:
	for entity in _entities:
		if not is_instance_valid(entity):
			continue
		if hand_area != null and entity in hand_area.cards:
			hand_area.remove_card(entity, false)
		entity.queue_free()
	_entities.clear()
	_card_views.clear()
	_instances.clear()


func get_instances() -> Array[CardInstance]:
	return _instances


func get_entities() -> Array[CardEntity]:
	return _entities


func get_card_views() -> Array[Card]:
	return _card_views.duplicate()


func can_register_existing_instance(card_inst: CardInstance, card: Card) -> bool:
	if (
		card_inst == null
		or card_inst.card_data == null
		or card == null
		or not is_instance_valid(card)
		or card.get_card_inst() != card_inst
	):
		return false

	var instance_registered := card_inst in _instances
	var view_registered := card in _card_views
	if instance_registered or view_registered:
		return instance_registered and view_registered
	return true


func register_existing_instance(card_inst: CardInstance, card: Card) -> bool:
	if not can_register_existing_instance(card_inst, card):
		return false
	if card_inst not in _instances:
		_instances.append(card_inst)
	if card not in _card_views:
		_card_views.append(card)
	card_inst.cur_zone = CardInstance.ZONE.HAND
	return true


func can_destroy_existing_instance(card_inst: CardInstance, card: Card) -> bool:
	return (
		card_inst != null
		and card != null
		and is_instance_valid(card)
		and card_inst in _instances
		and card in _card_views
		and card.get_card_inst() == card_inst
	)


func destroy_existing_instance(card_inst: CardInstance, card: Card) -> bool:
	if not can_destroy_existing_instance(card_inst, card):
		return false

	_instances.erase(card_inst)
	_card_views.erase(card)
	card_inst.cur_zone = CardInstance.ZONE.DISCARD
	card.cur_zone = null
	card.bind_drag_layer(null)
	card.queue_free()
	return true


func _add_new_instance_to_hand(instance: CardInstance) -> bool:
	if instance == null or hand_area.is_full():
		return false
	var entity: CardEntity = card_manager.create_card_entity(instance)
	if entity == null:
		return false
	entity.drag_layer = drag_layer
	if not hand_area.add_card(entity):
		entity.queue_free()
		return false
	_instances.append(instance)
	_entities.append(entity)
	return true


func _is_configured() -> bool:
	return card_manager != null and hand_area != null and drag_layer != null
