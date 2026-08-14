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
	if result == null or _board == null or _board.board_zone == null:
		return 0
	if result.kind != BoardPlacementResult.Kind.CHAIN_EXTENDED:
		return 0
	var added_card: Card = result.chain_tail
	if added_card == null:
		added_card = result.source_card
	if added_card == null:
		return 0
	var instance := added_card.get_card_inst()
	if instance == null:
		return 0
	var applied_count := _card_chain_rule_service.resolve_card_added(
		_board.board_zone.get_combat_card_chain(), instance
	)
	if applied_count > 0:
		added_card.refresh_display()
	card_chain_rules_applied.emit(result, applied_count)
	return applied_count
