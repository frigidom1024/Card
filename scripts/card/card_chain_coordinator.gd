class_name CardChainCoordinator
extends RefCounted

const CardChainRuleServiceScript := preload("res://scripts/card/card_chain_rule_service.gd")

## Coordinates card-chain reactions after Board commits a normal card placement.
## This is deliberately outside ExplorationCoordinator: exploration only reacts
## to the placement after card-domain effects have been resolved.
signal card_chain_rules_applied(result: BoardPlacementResult, applied_count: int)

var _board: Board
var _card_chain_rule_service := CardChainRuleServiceScript.new()


func configure(board: Board) -> bool:
	if board == null:
		return false
	if _board != null and _board.placement_committed.is_connected(_on_placement_committed):
		_board.placement_committed.disconnect(_on_placement_committed)
	_board = board
	if not _board.placement_committed.is_connected(_on_placement_committed):
		_board.placement_committed.connect(_on_placement_committed)
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


func _on_placement_committed(result: BoardPlacementResult) -> void:
	resolve_placement(result)
