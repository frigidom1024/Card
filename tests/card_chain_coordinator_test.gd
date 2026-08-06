extends SceneTree

const BoardScene := preload("res://scenes/game/board.tscn")
const CardEntityScene := preload("res://scenes/card_view/card_entity.tscn")
const CardChainCoordinatorScript := preload("res://scripts/card/card_chain_coordinator.gd")
const CardDataScript := preload("res://scripts/card/card_data.gd")
const CardInstanceScript := preload("res://scripts/card/card_instance.gd")
const NextCardPointBonusRuleScript := preload(
	"res://scripts/combatv2/card/rules/next_card_point_bonus_rule.gd"
)

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_board_placement_is_resolved_by_card_chain_coordinator()
	_test_guide_placement_does_not_resolve_normal_chain_rules()
	quit(1 if _failure_count > 0 else 0)


func _test_board_placement_is_resolved_by_card_chain_coordinator() -> void:
	var board := _make_board()
	var coordinator := CardChainCoordinatorScript.new()
	_expect(coordinator.configure(board), "card-chain coordinator configures with Board")
	var source := _make_card(board, 1)
	var rule := NextCardPointBonusRuleScript.new()
	rule.bonus_points = 2
	source.card_instance.card_data.effect_rules.append(rule)
	var added := _make_card(board, 1)
	board.cards.append_array([source, added])
	var result := BoardPlacementResult.new(
		BoardPlacementResult.Kind.CHAIN_EXTENDED, added, added, [added], []
	)
	var applied_counts: Array[int] = []
	coordinator.card_chain_rules_applied.connect(
		func(_result: BoardPlacementResult, count: int) -> void: applied_counts.append(count)
	)

	board.placement_committed.emit(result)

	_expect(applied_counts == [1], "Board placement invokes card-chain rules once")
	_expect(added.card_instance.current_points == 3, "rule modifies the newly added card")
	_expect(source.card_instance.get_rule_trigger_count(0) == 1, "source instance owns rule usage")
	board.queue_free()


func _test_guide_placement_does_not_resolve_normal_chain_rules() -> void:
	var board := _make_board()
	var coordinator := CardChainCoordinatorScript.new()
	coordinator.configure(board)
	var source := _make_card(board, 1)
	var rule := NextCardPointBonusRuleScript.new()
	rule.bonus_points = 2
	source.card_instance.card_data.effect_rules.append(rule)
	var guide := _make_card(board, 1)
	board.cards.append_array([source, guide])
	var result := BoardPlacementResult.new(
		BoardPlacementResult.Kind.GUIDE_RESOLVED, guide, guide, [guide], []
	)

	board.placement_committed.emit(result)

	_expect(guide.card_instance.current_points == 1, "GUIDE placement skips normal chain rules")
	_expect(source.card_instance.get_rule_trigger_count(0) == 0, "GUIDE placement does not consume rule use")
	board.queue_free()


func _make_board() -> Board:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	return board


func _make_card(board: Board, max_points: int) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	board.add_child(card)
	var data := CardDataScript.new()
	data.max_points = max_points
	card.bind_instance(CardInstanceScript.new(data))
	return card


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
