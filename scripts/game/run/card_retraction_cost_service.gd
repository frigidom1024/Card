class_name CardRetractionCostService
extends RefCounted

## Applies the current temporary chain-retraction rule: every card returned to
## hand costs two gold. The completed DragLayer transaction is the source of
## truth, so cancelled drags never charge the player.
signal retraction_cost_paid(cost: int, returned_count: int, remaining_gold: int)

const COST_PER_RETURNED_CARD := 2

var _player: PlayerData


func configure(player: PlayerData) -> bool:
    _player = player
    return _player != null


func get_returned_card_count(transaction: ChainRetractionTransaction) -> int:
    if transaction == null:
        return 0
    return 1 + transaction.returned_followers.size()


func get_cost(transaction: ChainRetractionTransaction) -> int:
    return get_returned_card_count(transaction) * COST_PER_RETURNED_CARD


func resolve_confirmed_chain_retraction(transaction: ChainRetractionTransaction) -> void:
    if _player == null or transaction == null:
        return
    var returned_count := get_returned_card_count(transaction)
    if returned_count <= 0:
        return
    var cost := get_cost(transaction)
    _player.gold -= cost
    retraction_cost_paid.emit(cost, returned_count, _player.gold)
