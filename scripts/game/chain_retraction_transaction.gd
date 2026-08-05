class_name ChainRetractionTransaction
extends RefCounted

## Immutable record of one completed player-initiated Board-chain retraction.
var removed_card: CardEntity
var returned_followers: Array[CardEntity]
var original_chain_size: int


func _init(
	removed: CardEntity = null,
	followers: Array[CardEntity] = [],
	chain_size: int = 0
) -> void:
	removed_card = removed
	returned_followers = followers.duplicate()
	original_chain_size = chain_size
