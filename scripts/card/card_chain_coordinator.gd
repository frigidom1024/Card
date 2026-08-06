class_name CardChainCoordinator
extends RefCounted

const CardChainRuleServiceScript := preload("res://scripts/card/card_chain_rule_service.gd")

## Resolves card-chain reactions after a committed normal card placement.
## PlacementPipelineCoordinator owns the Board signal subscription and invokes this explicitly.
signal card_chain_rules_applied(result: BoardPlacementResult, applied_count: int)

var _board: Board
var _card_chain_rule_service := CardChainRuleServiceScript.new()


func configure(board: Board) -> bool:
	if board == null:
		return false
	_board = board
	return true


func resolve_placement(result: BoardPlacementResult) -> int:
	if result == null or _board == null:
		return 0
	if result.kind != BoardPlacementResult.Kind.CHAIN_EXTENDED:
		return 0
	var added_entity := result.chain_tail
	if added_entity == null:
		added_entity = result.source_card
	if added_entity == null or added_entity.card_instance == null:
		return 0
	var applied_count := _card_chain_rule_service.resolve_card_added(
		_board.get_combat_card_chain(), added_entity.card_instance
	)
	card_chain_rules_applied.emit(result, applied_count)
	return applied_count
