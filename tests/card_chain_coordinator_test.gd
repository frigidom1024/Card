extends SceneTree

const BOARD_SCENE := preload("res://scenes/game/board.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const CARD_CHAIN_COORDINATOR := preload("res://scripts/card/card_chain_coordinator.gd")
const NEXT_CARD_POINT_BONUS_RULE := preload(
	"res://scripts/combatv2/card/rules/next_card_point_bonus_rule.gd"
)

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_explicit_placement_resolution_applies_rules_without_board_subscription()
	await _test_guide_placement_does_not_resolve_normal_chain_rules()
	quit(1 if _failure_count > 0 else 0)


func _test_explicit_placement_resolution_applies_rules_without_board_subscription() -> void:
	var board := _make_board()
	var coordinator := CARD_CHAIN_COORDINATOR.new()
	_expect(coordinator.configure(board), "card-chain coordinator configures with Board")
	var source := _make_card(CardData.CardType.ROOT, 1, "Source")
	var rule := NEXT_CARD_POINT_BONUS_RULE.new()
	rule.bonus_points = 2
	source.get_card_inst().card_data.effect_rules.append(rule)
	_move_card_to_anchor(board.board_zone, source, Vector2i(4, 4), 0)
	_expect(board.board_zone.add_card(source), "source ROOT enters BoardZone")

	var added := _make_card(CardData.CardType.NORMAL, 1, "Added")
	_move_card_to_anchor(board.board_zone, added, Vector2i(4, 2), 0)
	_expect(board.board_zone.add_card(added), "added NORMAL extends BoardZone chain")
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
	_expect(added.get_card_inst().current_points == 3, "rule modifies the exact added CardInstance")
	_expect(added.attack_label.text == "3", "rule refreshes the visible Card point label")
	_expect(source.get_card_inst().get_rule_trigger_count(0) == 1, "source instance owns rule usage")
	board.queue_free()
	await process_frame


func _test_guide_placement_does_not_resolve_normal_chain_rules() -> void:
	var board := _make_board()
	var coordinator := CARD_CHAIN_COORDINATOR.new()
	coordinator.configure(board)
	var source := _make_card(CardData.CardType.ROOT, 1, "Source")
	var rule := NEXT_CARD_POINT_BONUS_RULE.new()
	rule.bonus_points = 2
	source.get_card_inst().card_data.effect_rules.append(rule)
	_move_card_to_anchor(board.board_zone, source, Vector2i(4, 4), 0)
	_expect(board.board_zone.add_card(source), "source ROOT enters BoardZone for GUIDE test")

	var guide := _make_card(CardData.CardType.GUIDE, 1, "Guide")
	board.add_child(guide)
	var result := BoardPlacementResult.new(
		BoardPlacementResult.Kind.GUIDE_RESOLVED, guide, guide, [guide], []
	)
	coordinator.resolve_placement(result)

	_expect(guide.get_card_inst().current_points == 1, "GUIDE placement skips normal chain rules")
	_expect(source.get_card_inst().get_rule_trigger_count(0) == 0, "GUIDE placement does not consume rule use")
	board.queue_free()
	await process_frame


func _make_board() -> Board:
	var board := BOARD_SCENE.instantiate() as Board
	root.add_child(board)
	return board


func _make_card(card_type: CardData.CardType, max_points: int, card_name: String) -> Card:
	var data := CardData.new()
	data.card_type = card_type
	data.max_points = max_points
	data.card_name = card_name
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(CardInstance.new(data))
	return card


func _move_card_to_anchor(board_zone: BoardZone, card: Card, anchor: Vector2i, direction: int) -> void:
	var background := board_zone.back_ground
	var cell_size := background.cell_size
	var local_center: Vector2
	if posmod(direction, 4) % 2 == 0:
		local_center = Vector2((float(anchor.x) + 0.5) * cell_size, (float(anchor.y) + 1.0) * cell_size)
	else:
		local_center = Vector2((float(anchor.x) + 1.0) * cell_size, (float(anchor.y) + 0.5) * cell_size)
	var center := background.to_global(local_center)
	card.global_position = center - card.size * 0.5
	card.target_position = card.position
	card.get_card_inst().direction = direction


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
