class_name BoardPlacementResult
extends RefCounted

## Immutable summary of one successful Board placement transaction.
## Event contact is recorded here; the Board never resolves the event itself.
enum Kind {
	CHAIN_EXTENDED,
	GUIDE_RESOLVED,
}

var kind: Kind
var source_card: CardEntity
var chain_tail: CardEntity
var affected_cards: Array[CardEntity]
var newly_occupied_cells: Array[Vector2i]
var overlapped_event: EventInstance


func _init(
	initial_kind: Kind,
	initial_source_card: CardEntity,
	initial_chain_tail: CardEntity,
	initial_affected_cards: Array[CardEntity],
	initial_newly_occupied_cells: Array[Vector2i],
	initial_overlapped_event: EventInstance = null
) -> void:
	kind = initial_kind
	source_card = initial_source_card
	chain_tail = initial_chain_tail
	affected_cards = initial_affected_cards.duplicate()
	newly_occupied_cells = initial_newly_occupied_cells.duplicate()
	overlapped_event = initial_overlapped_event
