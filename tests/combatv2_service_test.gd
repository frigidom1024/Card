extends SceneTree

const CombatServiceScript = preload("res://scripts/combatv2/combat_service.gd")
const CombatStatsScript = preload("res://scripts/combatv2/combat_stats.gd")
const CombatStatsDataScript = preload("res://scripts/combatv2/combat_stats_data.gd")
const CombatResultScript = preload("res://scripts/combatv2/combat_result.gd")
const CombatStepScript = preload("res://scripts/combatv2/combat_step.gd")
const CombatEffectScript = preload("res://scripts/combatv2/card/combat_effect.gd")
const PreviousWeaponDamageDoubleRuleScript = preload(
	"res://scripts/combatv2/card/rules/previous_weapon_damage_double_rule.gd"
)
const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const MobDataScript = preload("res://scripts/game/event/encounter/mob_data.gd")
const MobActionScript = preload("res://scripts/game/event/encounter/mob_action.gd")

var _failure_count := 0


func _init() -> void:
	_test_root_damage_can_win_without_monster_action()
	_test_normal_card_and_monster_action_alternate()
	_test_defense_is_consumed_before_player_hp()
	_test_healing_is_capped_before_monster_action()
	_test_previous_weapon_rule_modifies_current_card_damage()
	_test_lethal_normal_card_skips_monster_counterattack()
	_test_lethal_monster_action_stops_remaining_cards()
	_test_retreat_result_keeps_combat_state_for_retry()
	_test_monster_strengthening_caps_stacks()
	_test_result_steps_and_inputs_are_isolated_snapshots()
	_test_missing_monster_action_records_an_empty_step()
	_test_monster_defense_action_resolves_after_player_card()
	_test_monster_heal_action_respects_current_hp()
	_test_root_only_chain_returns_retreat()
	call_deferred("_finish_tests")


func _test_root_damage_can_win_without_monster_action() -> void:
	var player := _make_stats(20, 20, 0, 0)
	var root := _make_card("Flame Root", CardData.CardType.ROOT, 10)
	var monster := _make_monster("Training Slime", 10, 0, [_attack(99)])

	var result := CombatServiceScript.new().resolve_encounter(player, [root], monster)

	_expect_result(result, CombatResultScript.Outcome.VICTORY, 1, 0, "root lethal victory")
	_expect_stats(result.player_stats_after, 20, 20, 0, 0, "root lethal final player stats")
	_expect_stats(result.monster_stats_after, 10, 0, 0, 0, "root lethal final monster stats")
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Flame Root",
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[10, 10, 0, 0],
		[10, 0, 0, 0],
		[_damage_effect(CombatEffect.Target.MONSTER, 10, CombatEffect.SourceType.ROOT_CARD)]
	)
	_expect(result.steps.size() == 1, "lethal root does not create a monster action step")


func _test_normal_card_and_monster_action_alternate() -> void:
	var player := _make_stats(20, 20, 0, 0)
	var root := _make_card("Quiet Root", CardData.CardType.ROOT)
	var slash := _make_card("Slash", CardData.CardType.NORMAL, 3)
	var monster := _make_monster("Wolf", 10, 0, [_attack(4)])

	var result := CombatServiceScript.new().resolve_encounter(player, [root, slash], monster)

	_expect_result(result, CombatResultScript.Outcome.RETREAT, 2, 0, "alternating combat retreats")
	_expect_stats(result.player_stats_after, 20, 16, 0, 0, "alternating combat final player stats")
	_expect_stats(result.monster_stats_after, 10, 7, 0, 0, "alternating combat final monster stats")
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Quiet Root",
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[]
	)
	_expect_step(
		result,
		1,
		CombatStepScript.Kind.PLAYER_CARD,
		"Slash",
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[10, 10, 0, 0],
		[10, 7, 0, 0],
		[_damage_effect(CombatEffect.Target.MONSTER, 3, CombatEffect.SourceType.PLAYER_CARD)]
	)
	_expect_step(
		result,
		2,
		CombatStepScript.Kind.MONSTER_ACTION,
		"Wolf",
		[20, 20, 0, 0],
		[20, 16, 0, 0],
		[10, 7, 0, 0],
		[10, 7, 0, 0],
		[_damage_effect(CombatEffect.Target.PLAYER, 4, CombatEffect.SourceType.MONSTER_ACTION)]
	)


func _test_defense_is_consumed_before_player_hp() -> void:
	var player := _make_stats(10, 10, 0, 0)
	var root := _make_card("Shield Root", CardData.CardType.ROOT)
	var guard := _make_card("Guard", CardData.CardType.NORMAL, 0, 5)
	var monster := _make_monster("Boar", 20, 0, [_attack(3)])

	var result := CombatServiceScript.new().resolve_encounter(player, [root, guard], monster)

	_expect_result(result, CombatResultScript.Outcome.RETREAT, 2, 0, "defense scenario retreats")
	_expect_stats(result.player_stats_after, 10, 10, 0, 2, "defense absorbs monster attack")
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Shield Root",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[]
	)
	_expect_step(
		result,
		1,
		CombatStepScript.Kind.PLAYER_CARD,
		"Guard",
		[10, 10, 0, 0],
		[10, 10, 0, 5],
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[_defense_effect(CombatEffect.Target.PLAYER, 5, CombatEffect.SourceType.PLAYER_CARD)]
	)
	_expect_step(
		result,
		2,
		CombatStepScript.Kind.MONSTER_ACTION,
		"Boar",
		[10, 10, 0, 5],
		[10, 10, 0, 2],
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[_damage_effect(CombatEffect.Target.PLAYER, 3, CombatEffect.SourceType.MONSTER_ACTION)]
	)


func _test_healing_is_capped_before_monster_action() -> void:
	var player := _make_stats(10, 8, 0, 0)
	var root := _make_card("Healing Root", CardData.CardType.ROOT)
	var recovery := _make_card("Recovery", CardData.CardType.NORMAL, 0, 0, 5)
	var monster := _make_monster("Bat", 20, 0, [_attack(2)])

	var result := CombatServiceScript.new().resolve_encounter(player, [root, recovery], monster)

	_expect_result(result, CombatResultScript.Outcome.RETREAT, 2, 0, "healing scenario retreats")
	_expect_stats(result.player_stats_after, 10, 8, 0, 0, "healing caps at max HP before damage")
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Healing Root",
		[10, 8, 0, 0],
		[10, 8, 0, 0],
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[]
	)
	_expect_step(
		result,
		1,
		CombatStepScript.Kind.PLAYER_CARD,
		"Recovery",
		[10, 8, 0, 0],
		[10, 10, 0, 0],
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[_heal_effect(CombatEffect.Target.PLAYER, 5, CombatEffect.SourceType.PLAYER_CARD)]
	)
	_expect_step(
		result,
		2,
		CombatStepScript.Kind.MONSTER_ACTION,
		"Bat",
		[10, 10, 0, 0],
		[10, 8, 0, 0],
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[_damage_effect(CombatEffect.Target.PLAYER, 2, CombatEffect.SourceType.MONSTER_ACTION)]
	)


func _test_previous_weapon_rule_modifies_current_card_damage() -> void:
	var player := _make_stats(10, 10, 0, 0)
	var root := _make_card("Combo Root", CardData.CardType.ROOT)
	var weapon := _make_card("Sword", CardData.CardType.NORMAL, 2, 0, 0, [CardData.CardTag.WEAPON])
	var finisher := _make_card(
		"Finisher",
		CardData.CardType.NORMAL,
		3,
		0,
		0,
		[],
		[PreviousWeaponDamageDoubleRuleScript.new()]
	)
	var monster := _make_monster("Knight", 8, 0, [_attack(1)])

	var result := CombatServiceScript.new().resolve_encounter(
		player, [root, weapon, finisher], monster
	)

	_expect_result(result, CombatResultScript.Outcome.VICTORY, 3, 0, "weapon combo wins")
	_expect_stats(result.player_stats_after, 10, 9, 0, 0, "weapon combo final player stats")
	_expect_stats(result.monster_stats_after, 8, 0, 0, 0, "weapon combo final monster stats")
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Combo Root",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[8, 8, 0, 0],
		[8, 8, 0, 0],
		[]
	)
	_expect_step(
		result,
		1,
		CombatStepScript.Kind.PLAYER_CARD,
		"Sword",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[8, 8, 0, 0],
		[8, 6, 0, 0],
		[_damage_effect(CombatEffect.Target.MONSTER, 2, CombatEffect.SourceType.PLAYER_CARD)]
	)
	_expect_step(
		result,
		2,
		CombatStepScript.Kind.MONSTER_ACTION,
		"Knight",
		[10, 10, 0, 0],
		[10, 9, 0, 0],
		[8, 6, 0, 0],
		[8, 6, 0, 0],
		[_damage_effect(CombatEffect.Target.PLAYER, 1, CombatEffect.SourceType.MONSTER_ACTION)]
	)
	_expect_step(
		result,
		3,
		CombatStepScript.Kind.PLAYER_CARD,
		"Finisher",
		[10, 9, 0, 0],
		[10, 9, 0, 0],
		[8, 6, 0, 0],
		[8, 0, 0, 0],
		[_damage_effect(CombatEffect.Target.MONSTER, 6, CombatEffect.SourceType.PLAYER_CARD)]
	)
	_expect(result.steps.size() == 4, "lethal combo card skips its following monster action")


func _test_lethal_normal_card_skips_monster_counterattack() -> void:
	var player := _make_stats(10, 10, 0, 0)
	var root := _make_card("Plain Root", CardData.CardType.ROOT)
	var heavy_slash := _make_card("Heavy Slash", CardData.CardType.NORMAL, 6)
	var monster := _make_monster("Glass Beast", 6, 0, [_attack(99)])

	var result := CombatServiceScript.new().resolve_encounter(player, [root, heavy_slash], monster)

	_expect_result(result, CombatResultScript.Outcome.VICTORY, 2, 0, "lethal normal card wins")
	_expect_stats(result.player_stats_after, 10, 10, 0, 0, "lethal normal card preserves player HP")
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Plain Root",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[6, 6, 0, 0],
		[6, 6, 0, 0],
		[]
	)
	_expect_step(
		result,
		1,
		CombatStepScript.Kind.PLAYER_CARD,
		"Heavy Slash",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[6, 6, 0, 0],
		[6, 0, 0, 0],
		[_damage_effect(CombatEffect.Target.MONSTER, 6, CombatEffect.SourceType.PLAYER_CARD)]
	)
	_expect(result.steps.size() == 2, "lethal normal card has no counterattack step")


func _test_lethal_monster_action_stops_remaining_cards() -> void:
	var player := _make_stats(10, 10, 0, 0)
	var root := _make_card("Risky Root", CardData.CardType.ROOT)
	var bait := _make_card("Bait", CardData.CardType.NORMAL)
	var unused_tail := _make_card("Unused Tail", CardData.CardType.NORMAL, 99)
	var monster := _make_monster("Executioner", 100, 0, [_attack(10)])

	var result := CombatServiceScript.new().resolve_encounter(
		player, [root, bait, unused_tail], monster
	)

	_expect_result(
		result, CombatResultScript.Outcome.DEFEAT, 2, 0, "lethal monster action defeats player"
	)
	_expect_stats(
		result.player_stats_after, 10, 0, 0, 0, "lethal monster action reduces player HP to zero"
	)
	_expect_stats(result.monster_stats_after, 100, 100, 0, 0, "defeat leaves monster unchanged")
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Risky Root",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[100, 100, 0, 0],
		[100, 100, 0, 0],
		[]
	)
	_expect_step(
		result,
		1,
		CombatStepScript.Kind.PLAYER_CARD,
		"Bait",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[100, 100, 0, 0],
		[100, 100, 0, 0],
		[]
	)
	_expect_step(
		result,
		2,
		CombatStepScript.Kind.MONSTER_ACTION,
		"Executioner",
		[10, 10, 0, 0],
		[10, 0, 0, 0],
		[100, 100, 0, 0],
		[100, 100, 0, 0],
		[_damage_effect(CombatEffect.Target.PLAYER, 10, CombatEffect.SourceType.MONSTER_ACTION)]
	)
	_expect(result.steps.size() == 3, "defeat stops the unprocessed tail card")


func _test_retreat_result_keeps_combat_state_for_retry() -> void:
	var player := _make_stats(10, 10, 0, 0)
	var root := _make_card("Retreat Root", CardData.CardType.ROOT)
	var poke := _make_card("Poke", CardData.CardType.NORMAL, 4)
	var tail_guard := _make_card("Tail Guard", CardData.CardType.NORMAL, 0, 2)
	var monster := _make_monster("Echo", 20, 0, [_attack(3)])
	var board: Array[CardInstance] = [root, poke, tail_guard]

	var result := CombatServiceScript.new().resolve_encounter(player, board, monster)

	_expect_result(
		result,
		CombatResultScript.Outcome.RETREAT,
		3,
		0,
		"card chain exhaustion returns RETREAT"
	)
	_expect_stats(result.player_stats_after, 10, 6, 0, 0, "retreat preserves combat damage before settlement")
	_expect_stats(result.monster_stats_after, 20, 16, 0, 0, "retreat keeps monster battle damage")
	_expect(result.monster_action_index_after == 0, "retreat snapshots the next monster action")


func _test_monster_strengthening_caps_stacks() -> void:
	var monster := _make_monster("Echo", 10, 0, [])

	_expect(monster.gain_enhancement(), "first strengthening increases the stack count")
	_expect(monster.gain_enhancement(), "second strengthening increases the stack count")
	_expect(not monster.gain_enhancement(), "normal echo strengthening stops at the cap")
	_expect(monster.enhancement_stacks == 2, "normal echo strengthening caps at two stacks")


func _test_result_steps_and_inputs_are_isolated_snapshots() -> void:
	var player := _make_stats(12, 12, 0, 2)
	var root := _make_card("Snapshot Root", CardData.CardType.ROOT, 3)
	var wait := _make_card("Wait", CardData.CardType.NORMAL)
	var monster := _make_monster("Armored Dummy", 10, 1, [_attack(4)])

	var result := CombatServiceScript.new().resolve_encounter(player, [root, wait], monster)

	_expect_result(result, CombatResultScript.Outcome.RETREAT, 2, 0, "snapshot scenario retreats")
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Snapshot Root",
		[12, 12, 0, 2],
		[12, 12, 0, 2],
		[10, 10, 0, 1],
		[10, 8, 0, 0],
		[_damage_effect(CombatEffect.Target.MONSTER, 3, CombatEffect.SourceType.ROOT_CARD)]
	)
	_expect_step(
		result,
		1,
		CombatStepScript.Kind.PLAYER_CARD,
		"Wait",
		[12, 12, 0, 2],
		[12, 12, 0, 2],
		[10, 8, 0, 0],
		[10, 8, 0, 0],
		[]
	)
	_expect_step(
		result,
		2,
		CombatStepScript.Kind.MONSTER_ACTION,
		"Armored Dummy",
		[12, 12, 0, 2],
		[12, 10, 0, 0],
		[10, 8, 0, 0],
		[10, 8, 0, 0],
		[_damage_effect(CombatEffect.Target.PLAYER, 4, CombatEffect.SourceType.MONSTER_ACTION)]
	)
	_expect_stats(player, 12, 12, 0, 2, "encounter does not mutate player input")
	_expect_stats(monster.stats, 10, 10, 0, 1, "encounter does not mutate monster input")
	_expect(root.card_data.damage == 3, "encounter does not mutate card input")
	result.steps[0].monster_after.hp = 0
	result.steps[2].player_after.hp = 0
	_expect(
		result.monster_stats_after.hp == 8,
		"result final monster stats are isolated from step snapshots"
	)
	_expect(
		result.player_stats_after.hp == 10,
		"result final player stats are isolated from step snapshots"
	)


func _test_missing_monster_action_records_an_empty_step() -> void:
	var player := _make_stats(10, 10, 0, 0)
	var root := _make_card("Silent Root", CardData.CardType.ROOT)
	var wait := _make_card("Wait", CardData.CardType.NORMAL)
	var monster := _make_monster("Passive Statue", 20, 0, [])

	var result := CombatServiceScript.new().resolve_encounter(player, [root, wait], monster)

	_expect_result(
		result, CombatResultScript.Outcome.RETREAT, 2, 0, "missing action scenario retreats"
	)
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Silent Root",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[]
	)
	_expect_step(
		result,
		1,
		CombatStepScript.Kind.PLAYER_CARD,
		"Wait",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[]
	)
	_expect_step(
		result,
		2,
		CombatStepScript.Kind.MONSTER_ACTION,
		"Passive Statue",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[]
	)


func _test_monster_defense_action_resolves_after_player_card() -> void:
	var player := _make_stats(10, 10, 0, 0)
	var root := _make_card("Tactical Root", CardData.CardType.ROOT)
	var poke := _make_card("Poke", CardData.CardType.NORMAL, 2)
	var monster := _make_monster("Guarded Goblin", 10, 0, [_defend(3)])

	var result := CombatServiceScript.new().resolve_encounter(player, [root, poke], monster)

	_expect_result(
		result, CombatResultScript.Outcome.RETREAT, 2, 0, "monster defense scenario retreats"
	)
	_expect_stats(result.player_stats_after, 10, 10, 0, 0, "monster defense final player stats")
	_expect_stats(result.monster_stats_after, 10, 8, 0, 3, "monster defense final monster stats")
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Tactical Root",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[]
	)
	_expect_step(
		result,
		1,
		CombatStepScript.Kind.PLAYER_CARD,
		"Poke",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[10, 8, 0, 0],
		[_damage_effect(CombatEffect.Target.MONSTER, 2, CombatEffect.SourceType.PLAYER_CARD)]
	)
	_expect_step(
		result,
		2,
		CombatStepScript.Kind.MONSTER_ACTION,
		"Guarded Goblin",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[10, 8, 0, 0],
		[10, 8, 0, 3],
		[_defense_effect(CombatEffect.Target.MONSTER, 3, CombatEffect.SourceType.MONSTER_ACTION)]
	)


func _test_monster_heal_action_respects_current_hp() -> void:
	var player := _make_stats(10, 10, 0, 0)
	var root := _make_card("Sustain Root", CardData.CardType.ROOT)
	var poke := _make_card("Poke", CardData.CardType.NORMAL, 1)
	var monster := _make_monster("Medic Slime", 10, 0, [_heal(3)])
	monster.stats.hp = 6

	var result := CombatServiceScript.new().resolve_encounter(player, [root, poke], monster)

	_expect_result(
		result, CombatResultScript.Outcome.RETREAT, 2, 0, "monster heal scenario retreats"
	)
	_expect_stats(result.player_stats_after, 10, 10, 0, 0, "monster heal final player stats")
	_expect_stats(result.monster_stats_after, 10, 8, 0, 0, "monster heal final monster stats")
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Sustain Root",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[10, 6, 0, 0],
		[10, 6, 0, 0],
		[]
	)
	_expect_step(
		result,
		1,
		CombatStepScript.Kind.PLAYER_CARD,
		"Poke",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[10, 6, 0, 0],
		[10, 5, 0, 0],
		[_damage_effect(CombatEffect.Target.MONSTER, 1, CombatEffect.SourceType.PLAYER_CARD)]
	)
	_expect_step(
		result,
		2,
		CombatStepScript.Kind.MONSTER_ACTION,
		"Medic Slime",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[10, 5, 0, 0],
		[10, 8, 0, 0],
		[_heal_effect(CombatEffect.Target.MONSTER, 3, CombatEffect.SourceType.MONSTER_ACTION)]
	)


func _test_root_only_chain_returns_retreat() -> void:
	var player := _make_stats(10, 10, 0, 0)
	var root := _make_card("Only Root", CardData.CardType.ROOT)
	var monster := _make_monster("Endless Wall", 20, 0, [])
	var board: Array[CardInstance] = [root]

	var result := CombatServiceScript.new().resolve_encounter(player, board, monster)

	_expect_result(result, CombatResultScript.Outcome.RETREAT, 1, 0, "root-only chain retreats")
	_expect_step(
		result,
		0,
		CombatStepScript.Kind.ROOT_CARD,
		"Only Root",
		[10, 10, 0, 0],
		[10, 10, 0, 0],
		[20, 20, 0, 0],
		[20, 20, 0, 0],
		[]
	)
	_expect(result.steps.size() == 1, "a nonlethal root does not receive a monster action")


func _expect_result(
	result: CombatResult,
	expected_outcome: CombatResult.Outcome,
	expected_processed_card_count: int,
	expected_penalty_count: int,
	description: String
) -> void:
	_expect(result != null, "%s returns a result" % description)
	if result == null:
		return
	_expect(result.outcome == expected_outcome, "%s has the expected outcome" % description)
	_expect(
		result.processed_card_count == expected_processed_card_count,
		"%s has the expected processed card count" % description
	)
	_expect(
		result.penalties.size() == expected_penalty_count,
		"%s has the expected penalty count" % description
	)


func _expect_step(
	result: CombatResult,
	index: int,
	expected_kind: CombatStep.Kind,
	expected_source_name: String,
	expected_player_before: Array[int],
	expected_player_after: Array[int],
	expected_monster_before: Array[int],
	expected_monster_after: Array[int],
	expected_effects: Array[Dictionary]
) -> void:
	_expect(result != null and result.steps.size() > index, "step %d exists" % index)
	if result == null or result.steps.size() <= index:
		return
	var step: CombatStep = result.steps[index]
	_expect(step != null, "step %d is not null" % index)
	if step == null:
		return
	_expect(step.kind == expected_kind, "step %d kind matches" % index)
	_expect(step.source_name == expected_source_name, "step %d source name matches" % index)
	_expect_stats(
		step.player_before,
		expected_player_before[0],
		expected_player_before[1],
		expected_player_before[2],
		expected_player_before[3],
		"step %d player before" % index
	)
	_expect_stats(
		step.player_after,
		expected_player_after[0],
		expected_player_after[1],
		expected_player_after[2],
		expected_player_after[3],
		"step %d player after" % index
	)
	_expect_stats(
		step.monster_before,
		expected_monster_before[0],
		expected_monster_before[1],
		expected_monster_before[2],
		expected_monster_before[3],
		"step %d monster before" % index
	)
	_expect_stats(
		step.monster_after,
		expected_monster_after[0],
		expected_monster_after[1],
		expected_monster_after[2],
		expected_monster_after[3],
		"step %d monster after" % index
	)
	_expect(step.effects.size() == expected_effects.size(), "step %d effect count matches" % index)
	for effect_index in mini(step.effects.size(), expected_effects.size()):
		var actual: CombatEffect = step.effects[effect_index]
		var expected := expected_effects[effect_index]
		_expect(actual != null, "step %d effect %d exists" % [index, effect_index])
		if actual == null:
			continue
		_expect(
			actual.type == expected.type, "step %d effect %d type matches" % [index, effect_index]
		)
		_expect(
			actual.target == expected.target,
			"step %d effect %d target matches" % [index, effect_index]
		)
		_expect(
			actual.value == expected.value,
			"step %d effect %d value matches" % [index, effect_index]
		)
		_expect(
			actual.source_type == expected.source_type,
			"step %d effect %d source type matches" % [index, effect_index]
		)
		_expect(
			actual.source_name == expected_source_name,
			"step %d effect %d source name matches" % [index, effect_index]
		)


func _expect_stats(
	stats: CombatStats, max_hp: int, hp: int, attack: int, defense: int, description: String
) -> void:
	_expect(stats != null, "%s stats exist" % description)
	if stats == null:
		return
	_expect(stats.max_hp == max_hp, "%s max HP matches" % description)
	_expect(stats.hp == hp, "%s HP matches" % description)
	_expect(stats.attack == attack, "%s attack matches" % description)
	_expect(stats.defense == defense, "%s defense matches" % description)


func _make_stats(max_hp: int, hp: int, attack: int, defense: int) -> CombatStats:
	var stats := CombatStatsScript.new()
	stats.max_hp = max_hp
	stats.hp = hp
	stats.attack = attack
	stats.defense = defense
	return stats


func _make_card(
	card_name: String,
	card_type: CardData.CardType,
	damage: int = 0,
	defense: int = 0,
	heal: int = 0,
	tags: Array[CardData.CardTag] = [],
	effect_rules: Array[CardRule] = []
) -> CardInstance:
	var data := CardDataScript.new()
	data.card_name = card_name
	data.card_type = card_type
	data.damage = damage
	data.defense = defense
	data.heal = heal
	data.tags = tags
	data.effect_rules = effect_rules
	return CardInstanceScript.new(data)


func _make_monster(
	mob_name: String, hp: int, defense: int, actions: Array[MobAction]
) -> MobInstance:
	var stats_data := CombatStatsDataScript.new()
	stats_data.max_hp = hp
	stats_data.defense = defense
	var data := MobDataScript.new()
	data.mob_name = mob_name
	data.base_stats = stats_data
	data.actions = actions
	return data.create_instance()


func _attack(value: int) -> MobAction:
	var action := MobActionScript.new()
	action.type = MobAction.Type.ATTACK
	action.value = value
	return action


func _defend(value: int) -> MobAction:
	var action := MobActionScript.new()
	action.type = MobAction.Type.DEFEND
	action.value = value
	return action


func _heal(value: int) -> MobAction:
	var action := MobActionScript.new()
	action.type = MobAction.Type.HEAL
	action.value = value
	return action


func _damage_effect(
	target: CombatEffect.Target, value: int, source_type: CombatEffect.SourceType
) -> Dictionary:
	return {
		"type": CombatEffect.Type.DAMAGE,
		"target": target,
		"value": value,
		"source_type": source_type
	}


func _defense_effect(
	target: CombatEffect.Target, value: int, source_type: CombatEffect.SourceType
) -> Dictionary:
	return {
		"type": CombatEffect.Type.ADD_DEFENSE,
		"target": target,
		"value": value,
		"source_type": source_type,
	}


func _heal_effect(
	target: CombatEffect.Target, value: int, source_type: CombatEffect.SourceType
) -> Dictionary:
	return {
		"type": CombatEffect.Type.HEAL, "target": target, "value": value, "source_type": source_type
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)


func _finish_tests() -> void:
	quit(0 if _failure_count == 0 else 1)
