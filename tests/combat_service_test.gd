extends SceneTree

const CombatEffectScript = preload("res://scripts/combat/combat_effect.gd")
const CombatPenaltyScript = preload("res://scripts/combat/combat_penalty.gd")
const CombatResultScript = preload("res://scripts/combat/combat_result.gd")
const CombatStateScript = preload("res://scripts/combat/combat_state.gd")
const CombatStatsScript = preload("res://scripts/combat/combat_stats.gd")
const CombatStepScript = preload("res://scripts/combat/combat_step.gd")
const MobDataScript = preload("res://scripts/game/event/mob_data.gd")
const CombatStatsDataScript = preload("res://scripts/combat/combat_stats_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")

var _failure_count := 0


func _init() -> void:
	_test_combat_effect()
	_test_combat_stats_runtime_copy()
	_test_combat_penalty()
	_test_combat_step_snapshots()
	_test_combat_result_ownership()
	_test_combat_state_foundation()
	call_deferred("_finish_tests")


func _test_combat_effect() -> void:
	var effect := CombatEffectScript.new(
		CombatEffectScript.Type.DAMAGE,
		CombatEffectScript.Target.MONSTER,
		4,
		CombatEffectScript.SourceType.PLAYER_CARD,
		"Test Card"
	)
	_expect(effect.type == CombatEffectScript.Type.DAMAGE, "combat effect carries its type")
	_expect(effect.target == CombatEffectScript.Target.MONSTER, "combat effect carries its target")
	_expect(effect.value == 4, "combat effect carries its value")
	_expect(
		effect.source_type == CombatEffectScript.SourceType.PLAYER_CARD,
		"combat effect carries its source type"
	)
	_expect(effect.source_name == "Test Card", "combat effect carries its source name")

	var clamped := CombatEffectScript.new(
		CombatEffectScript.Type.HEAL,
		CombatEffectScript.Target.PLAYER,
		-2,
		CombatEffectScript.SourceType.SYSTEM
	)
	_expect(clamped.value == 0, "combat effects clamp negative values")
	_expect(effect.has_method(&"duplicate_runtime"), "combat effects expose runtime duplication")
	if effect.has_method(&"duplicate_runtime"):
		var copy: CombatEffect = effect.call(&"duplicate_runtime")
		effect.value = 99
		effect.source_name = "Mutated Card"
		_expect(copy != effect, "runtime effect duplication creates a distinct object")
		_expect(
			copy.value == 4 and copy.source_name == "Test Card",
			"runtime effect copies preserve their original values"
		)


func _test_combat_stats_runtime_copy() -> void:
	var source := CombatStatsScript.new()
	source.max_hp = 20
	source.hp = 9
	source.attack = 7
	source.defense = 3

	var copy := source.duplicate_runtime()
	copy.take_damage(5)

	_expect(copy != source, "runtime stats duplication creates a distinct object")
	_expect(copy.max_hp == 20 and copy.attack == 7, "runtime copies preserve maximum HP and attack")
	_expect(copy.hp != source.hp, "runtime copies can change independently")
	_expect(source.hp == 9 and source.defense == 3, "runtime copy does not mutate source stats")


func _test_combat_penalty() -> void:
	var penalty := CombatPenaltyScript.new(
		CombatPenaltyScript.Type.REMOVE_CARD, 1, CombatPenaltyScript.Target.TAIL_OF_CARD_CHAIN
	)
	_expect(
		penalty.type == CombatPenaltyScript.Type.REMOVE_CARD, "retreat penalty carries its type"
	)
	_expect(penalty.amount == 1, "retreat penalty carries its amount")
	_expect(
		penalty.target == CombatPenaltyScript.Target.TAIL_OF_CARD_CHAIN,
		"retreat penalty carries its target"
	)

	var clamped := CombatPenaltyScript.new(
		CombatPenaltyScript.Type.REMOVE_CARD, -1, CombatPenaltyScript.Target.TAIL_OF_CARD_CHAIN
	)
	_expect(clamped.amount == 0, "combat penalties clamp negative amounts")
	_expect(penalty.has_method(&"duplicate_runtime"), "combat penalties expose runtime duplication")
	if penalty.has_method(&"duplicate_runtime"):
		var copy: CombatPenalty = penalty.call(&"duplicate_runtime")
		penalty.amount = 99
		_expect(copy != penalty, "runtime penalty duplication creates a distinct object")
		_expect(copy.amount == 1, "runtime penalty copies preserve their original amount")


func _test_combat_step_snapshots() -> void:
	var player_before := _make_stats(20, 15, 4, 2)
	var player_after := _make_stats(20, 15, 4, 6)
	var monster_before := _make_stats(12, 12, 3, 1)
	var monster_after := _make_stats(12, 8, 3, 0)
	var effect := CombatEffectScript.new(
		CombatEffectScript.Type.DAMAGE,
		CombatEffectScript.Target.MONSTER,
		4,
		CombatEffectScript.SourceType.ROOT_CARD,
		"Root"
	)
	var effects: Array[CombatEffect] = [effect]
	var step := CombatStepScript.new(
		CombatStepScript.Kind.ROOT_CARD,
		"Root",
		effects,
		player_before,
		player_after,
		monster_before,
		monster_after
	)

	player_before.hp = 1
	player_after.defense = 0
	monster_before.hp = 1
	monster_after.hp = 1
	effect.value = 99
	effect.source_name = "Mutated Root"
	effects.clear()

	_expect(
		step.kind == CombatStepScript.Kind.ROOT_CARD and step.source_name == "Root",
		"combat step carries its identity"
	)
	_expect(
		(
			step.effects.size() == 1
			and step.effects[0] != effect
			and step.effects[0].value == 4
			and step.effects[0].source_name == "Root"
		),
		"combat step deep-copies effect snapshots"
	)
	_expect(
		step.player_before.hp == 15 and step.player_after.defense == 6,
		"combat step owns player snapshots"
	)
	_expect(
		step.monster_before.hp == 12 and step.monster_after.hp == 8,
		"combat step owns monster snapshots"
	)
	_expect(step.has_method(&"duplicate_runtime"), "combat steps expose runtime duplication")
	if step.has_method(&"duplicate_runtime"):
		var copy: CombatStep = step.call(&"duplicate_runtime")
		step.source_name = "Mutated Step"
		step.effects[0].value = 0
		step.player_before.hp = 0
		step.monster_after.hp = 0
		_expect(
			copy != step and copy.source_name == "Root", "runtime step duplication copies identity"
		)
		_expect(
			(
				copy.effects[0].value == 4
				and copy.player_before.hp == 15
				and copy.monster_after.hp == 8
			),
			"runtime step copies isolate effects and stat snapshots"
		)


func _test_combat_result_ownership() -> void:
	var player_after := _make_stats(20, 11, 4, 0)
	var monster_after := _make_stats(12, 0, 3, 0)
	var effect := CombatEffectScript.new(
		CombatEffectScript.Type.DAMAGE,
		CombatEffectScript.Target.MONSTER,
		4,
		CombatEffectScript.SourceType.ROOT_CARD,
		"Root"
	)
	var effects: Array[CombatEffect] = [effect]
	var step := CombatStepScript.new(
		CombatStepScript.Kind.ROOT_CARD,
		"Root",
		effects,
		player_after,
		player_after,
		monster_after,
		monster_after
	)
	var steps: Array[CombatStep] = [step]
	var penalty := CombatPenaltyScript.new(
		CombatPenaltyScript.Type.REMOVE_CARD, 1, CombatPenaltyScript.Target.TAIL_OF_CARD_CHAIN
	)
	var penalties: Array[CombatPenalty] = [penalty]
	var result := CombatResultScript.new(
		CombatResultScript.Outcome.RETREAT, player_after, monster_after, steps, 1, penalties
	)

	player_after.hp = 1
	monster_after.hp = 5
	step.source_name = "Mutated Step"
	step.effects[0].value = 99
	step.player_before.hp = 1
	penalty.amount = 99
	steps.clear()
	penalties.clear()

	_expect(
		result.outcome == CombatResultScript.Outcome.RETREAT, "combat result carries its outcome"
	)
	_expect(
		result.player_stats_after.hp == 11 and result.monster_stats_after.hp == 0,
		"combat result owns final stat snapshots"
	)
	_expect(
		(
			result.steps.size() == 1
			and result.steps[0] != step
			and result.steps[0].source_name == "Root"
			and result.steps[0].effects[0].value == 4
			and result.steps[0].player_before.hp == 11
		),
		"combat result deep-copies step snapshots"
	)
	_expect(
		(
			result.penalties.size() == 1
			and result.penalties[0] != penalty
			and result.penalties[0].amount == 1
		),
		"combat result deep-copies penalty snapshots"
	)
	_expect(result.processed_card_count == 1, "combat result counts the resolved root card")


func _test_combat_state_foundation() -> void:
	var player_stats := _make_stats(20, 9, 5, 3)
	var monster_stats_data := CombatStatsDataScript.new()
	monster_stats_data.max_hp = 12
	monster_stats_data.attack = 4
	monster_stats_data.defense = 1
	var monster_data := MobDataScript.new()
	monster_data.base_stats = monster_stats_data
	var source_monster := monster_data.create_instance()
	source_monster.stats.hp = 7
	source_monster.action_index = 2
	var first_card := CardInstanceScript.new(null)
	var second_card := CardInstanceScript.new(null)
	var cards: Array[CardInstance] = [first_card, second_card]
	var state := CombatStateScript.new(player_stats, source_monster, cards)

	cards.clear()
	source_monster.stats.hp = 1
	source_monster.action_index = 0

	_expect(state.player_stats == player_stats, "combat state stores already-isolated player stats")
	_expect(
		state.monster != source_monster, "combat state does not retain the caller-owned monster"
	)
	_expect(
		state.monster.stats.hp == 7 and state.monster.action_index == 2,
		"combat state preserves encounter-local monster state"
	)
	_expect(
		state.cards.size() == 2 and state.cards[0] == first_card and state.cards[1] == second_card,
		"combat state owns the ordered card array"
	)
	_expect(state.remaining_cards.size() == 2, "combat state starts with every card remaining")
	_expect(
		state.resolved_cards.is_empty() and state.steps.is_empty(),
		"combat state starts with empty resolution history"
	)


func _make_stats(max_hp: int, hp: int, attack: int, defense: int) -> CombatStats:
	var stats := CombatStatsScript.new()
	stats.max_hp = max_hp
	stats.hp = hp
	stats.attack = attack
	stats.defense = defense
	return stats


func _finish_tests() -> void:
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
