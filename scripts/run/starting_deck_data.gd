class_name StartingDeckData
extends Resource


@export var deck_id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var starter_cards: Array[CardData] = []
@export var playstyle_tags: PackedStringArray = []
@export var is_unlocked := true


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if deck_id.strip_edges().is_empty():
		errors.append("deck_id is empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name is empty")
	if starter_cards.is_empty():
		errors.append("starter_cards is empty")

	var root_count := 0
	for card in starter_cards:
		if card == null:
			errors.append("starter_cards contains null")
			continue
		if card.card_type == CardData.CardType.ROOT:
			root_count += 1

	if root_count != 1:
		errors.append("starter_cards must contain exactly one ROOT card")
	return errors


func get_root_card() -> CardData:
	if not validate().is_empty():
		return null
	for card in starter_cards:
		if card.card_type == CardData.CardType.ROOT:
			return card
	return null


func get_remaining_starter_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	var root_card := get_root_card()
	if root_card == null:
		return result
	for card in starter_cards:
		if card != root_card:
			result.append(card)
	return result
