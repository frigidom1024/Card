extends SceneTree

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_context_owns_one_runtime_graph()
	await _test_seeded_random_streams_are_replayable()
	quit(1 if _failure_count > 0 else 0)


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


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)