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
	await _test_explicit_placement_resolution_applies_rules_without_board_subscription()
	_test_guide_placement_does_not_resolve_normal_chain_rules()
	quit(1 if _failure_count > 0 else 0)


func _test_explicit_placement_resolution_applies_rules_without_board_subscription() -> void:
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

	var has_card_chain_subscription := false
	for connection in board.placement_committed.get_connections():
		if connection.callable.get_object() == coordinator:
			has_card_chain_subscription = true
	_expect(not has_card_chain_subscription, "CardChainCoordinator does not subscribe to Board placement commits")

	_expect(coordinator.resolve_placement(result) == 1, "explicit placement resolution applies card-chain rules")
	_expect(applied_counts == [1], "explicit placement resolution emits the applied rule count")
	_expect(added.card_instance.current_points == 3, "rule modifies the newly added card")
	await process_frame
	_expect(
		_combat_tag_value(added) == "3",
		"card-chain point bonus refreshes the added card combat tag"
	)
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

	coordinator.resolve_placement(result)

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


func _combat_tag_value(card: CardEntity) -> String:
	var tag_container := card.get_node_or_null("CombatTagAnchor/TagContainer") as Container
	if tag_container == null or tag_container.get_child_count() == 0:
		return ""
	var tag := tag_container.get_child(0) as Control
	var value_label := tag.get_node_or_null("ValueLabel") as Label if tag != null else null
	return value_label.text if value_label != null else ""


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
