extends SceneTree

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_context_rejects_null_and_repeated_configuration()
	await _test_context_owns_one_runtime_graph()
	await _test_seeded_random_streams_are_replayable()
	quit(1 if _failure_count > 0 else 0)


func _test_context_rejects_null_and_repeated_configuration() -> void:
	var context := RunContext.new()
	var player := PlayerData.new()
	var stats := CombatStats.new()
	var cards := RunCardService.new()
	var flow := EncounterCombatFlowCoordinator.new(CombatService2.new())
	var interactions := EventInteractionController.new()
	var random := RunRandomService.new()
	_expect(
		not context.configure(player, stats, cards, flow, interactions, null),
		"run context rejects null dependencies"
	)
	_expect(not context.is_valid(), "rejected run context remains invalid")
	_expect(
		context.configure(player, stats, cards, flow, interactions, random),
		"run context accepts the first complete configuration"
	)
	var replacement_player := PlayerData.new()
	var replacement_stats := CombatStats.new()
	var replacement_cards := RunCardService.new()
	var replacement_flow := EncounterCombatFlowCoordinator.new(CombatService2.new())
	var replacement_interactions := EventInteractionController.new()
	var replacement_random := RunRandomService.new()
	_expect(
		not context.configure(
			replacement_player,
			replacement_stats,
			replacement_cards,
			replacement_flow,
			replacement_interactions,
			replacement_random
		),
		"run context rejects repeated configuration"
	)
	_expect(context.player_data == player, "repeated configuration cannot replace player data")
	_expect(context.player_stats == stats, "repeated configuration cannot replace player stats")
	_expect(context.card_service == cards, "repeated configuration cannot replace card service")
	_expect(context.combat_flow == flow, "repeated configuration cannot replace combat flow")
	_expect(
		context.event_interaction_controller == interactions,
		"repeated configuration cannot replace interaction controller"
	)
	_expect(context.random == random, "repeated configuration cannot replace random service")

func _test_context_owns_one_runtime_graph() -> void:
	var context := RunContext.new()
	var player := PlayerData.new()
	var stats := CombatStats.new()
	var cards := RunCardService.new()
	var flow := EncounterCombatFlowCoordinator.new(CombatService2.new())
	var interactions := EventInteractionController.new()
	var random := RunRandomService.new()
	_expect(
		context.configure(player, stats, cards, flow, interactions, random),
		"run context accepts a complete runtime graph"
	)
	_expect(context.is_valid(), "run context reports a complete runtime graph as valid")
	_expect(context.player_data == player, "run context preserves the runtime player reference")
	_expect(context.player_stats == stats, "run context preserves the runtime stats reference")
	_expect(context.card_service == cards, "run context preserves the card service reference")
	_expect(
		context.event_interaction_controller == interactions,
		"run context preserves the interaction controller reference"
	)
	_expect(context.combat_flow == flow, "run context preserves the combat flow reference")
	_expect(context.random == random, "run context preserves the random service reference")


func _test_seeded_random_streams_are_replayable() -> void:
	var first := RunRandomService.new()
	var second := RunRandomService.new()
	first.configure(12345)
	second.configure(12345)
	_expect(
		first.market_rng().randi() == second.market_rng().randi(),
		"seeded market streams reproduce the same result"
	)
	_expect(
		first.treasure_rng().randi() == second.treasure_rng().randi(),
		"seeded treasure streams reproduce the same result"
	)
	_expect(
		first.encounter_reward_rng().randi() == second.encounter_reward_rng().randi(),
		"seeded encounter reward streams reproduce the same result"
	)
	_expect(
		first.market_rng() != first.treasure_rng()
			and first.treasure_rng() != first.encounter_reward_rng(),
		"run random service owns independent RNG objects"
	)
	for _index in range(4):
		first.market_rng().randi()
	_expect(
		first.treasure_rng().randi() == second.treasure_rng().randi(),
		"consuming the market stream does not advance the treasure stream"
	)
	for _index in range(3):
		first.treasure_rng().randi()
	_expect(
		first.encounter_reward_rng().randi() == second.encounter_reward_rng().randi(),
		"consuming the treasure stream does not advance encounter rewards"
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)