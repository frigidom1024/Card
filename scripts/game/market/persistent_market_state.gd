class_name PersistentMarketState
extends RefCounted


const OFFER_SLOT_COUNT := 3

var offers: Array[CardData] = []
var _eligible_cards: Array[CardData] = []
var _rng: RandomNumberGenerator
var _progression: RunProgressionService


func initialize(
	card_library: CardLibrary,
	source_rng: RandomNumberGenerator,
	progression: RunProgressionService = null
) -> void:
	_rng = source_rng
	_progression = progression
	_eligible_cards.clear()
	if card_library != null:
		for card_data in card_library.cards:
			if card_data != null and card_data.card_type != CardData.CardType.ROOT:
				_eligible_cards.append(card_data)
	refresh_offers()


func get_offer(slot_index: int) -> CardData:
	if slot_index < 0 or slot_index >= offers.size():
		return null
	return offers[slot_index]


func replace_offer(slot_index: int) -> CardData:
	if slot_index < 0 or slot_index >= offers.size():
		return null
	var excluded: Array[CardData] = []
	for index in offers.size():
		if index != slot_index and offers[index] != null:
			excluded.append(offers[index])
	var replacement := _draw_offer(excluded)
	offers[slot_index] = replacement
	return replacement


func refresh_offers() -> void:
	offers.clear()
	var selected: Array[CardData] = []
	for _slot_index in OFFER_SLOT_COUNT:
		var card_data := _draw_offer(selected)
		if card_data == null:
			break
		offers.append(card_data)
		selected.append(card_data)


func _draw_offer(excluded: Array[CardData]) -> CardData:
	if _eligible_cards.is_empty():
		return null
	var candidates: Array[CardData] = []
	for card_data in _eligible_cards:
		if card_data not in excluded and _get_card_weight(card_data) > 0:
			candidates.append(card_data)
	if candidates.is_empty():
		for card_data in _eligible_cards:
			if _get_card_weight(card_data) > 0:
				candidates.append(card_data)
	if candidates.is_empty():
		return null
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()

	var total_weight := 0
	for card_data in candidates:
		total_weight += _get_card_weight(card_data)
	var roll := _rng.randi_range(1, total_weight)
	var cumulative := 0
	for card_data in candidates:
		cumulative += _get_card_weight(card_data)
		if roll <= cumulative:
			return card_data
	return candidates.back()


func _get_card_weight(card_data: CardData) -> int:
	if card_data == null:
		return 0
	return _progression.get_card_rarity_weight(card_data) if _progression != null else 1
