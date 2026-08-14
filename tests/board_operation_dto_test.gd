extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_dto_assertions()
	await process_frame
	quit()


func _run_dto_assertions() -> void:
	var card := Card.new()
	var instance := CardInstance.new(CardData.new())
	card.bind_card_inst(instance)

	var placement := BoardCardPlacement.new()
	placement.card = card
	placement.card_inst = instance
	placement.kind = BoardCardPlacement.Kind.GUIDE_SHIFTED
	placement.occupied_cells = [Vector2i(1, 2)]
	placement.affected_cards = [card]
	placement.chain_tail = card
	assert(placement.card == card)
	assert(placement.card_inst == instance)

	var retraction := BoardCardRetraction.new()
	retraction.removed_card = card
	retraction.followers_to_return = [card]
	retraction.original_chain_size = 2
	assert(retraction.followers_to_return[0] is Card)

	var result := BoardPlacementResult.new(
		BoardPlacementResult.Kind.GUIDE_RESOLVED,
		card,
		card,
		[card],
		[Vector2i(1, 2)],
		null
	)
	assert(result.source_card is Card)

	var transaction := ChainRetractionTransaction.new(card, [card], 2)
	assert(transaction.removed_card is Card)
	card.free()
