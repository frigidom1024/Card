extends SceneTree

const CombatServiceScript = preload("res://scripts/combatv2/combat_service.gd")
const CombatStatsScript = preload("res://scripts/combatv2/combat_stats.gd")
const CombatStatsDataScript = preload("res://scripts/combatv2/combat_stats_data.gd")
const CombatResultScript = preload("res://scripts/combatv2/combat_result.gd")
const CombatStepScript = preload("res://scripts/combatv2/combat_step.gd")
const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const MobDataScript = preload("res://scripts/game/event/encounter/mob_data.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_head_card_resolves_before_older_cards()
	_test_smaller_card_is_depleted_and_leaves_remaining_echo_hp()
	_test_equal_points_defeat_echo_and_deplete_card()
	_test_larger_card_keeps_remaining_points_after_victory()
	_test_armor_absorbs_echo_power_before_card_points()
	_test_depleted_root_is_reported_for_settlement()
	_test_regular_echo_actions_do_not_damage_player_or_create_steps()
	_test_point_clash_trace_only_reports_damage_to_echo()
	_test_retreat_enhancement_increases_echo_health_and_caps()
	quit(1 if _failure_count > 0 else 0)


func _test_head_card_resolves_before_older_cards() -> void:
	var root := _make_card("Root", CardData.CardType.ROOT, 2)
	var middle := _make_card("Middle", CardData.CardType.NORMAL, 5)
	var head := _make_card("Head", CardData.CardType.NORMAL, 1)

	var result := _resolve([root, middle, head], _make_monster("Echo", 1))

	_expect(result.outcome == CombatResultScript.Outcome.VICTORY, "head card can win immediately")
	_expect(result.processed_card_count == 1, "only the head card resolves on an immediate victory")
	_expect(result.steps.size() == 1, "immediate victory has one clash step")
	_expect(result.steps[0].kind == CombatStepScript.Kind.PLAYER_CARD, "head uses player-card step")
	_expect(result.steps[0].source_name == "Head", "head is the first resolved source")
	_expect(middle.current_points == 5, "unresolved middle card keeps its points")
	_expect(root.current_points == 2, "unresolved root keeps its points")
	_expect(head.current_points == 0, "equal head point comparison depletes the head")


func _test_smaller_card_is_depleted_and_leaves_remaining_echo_hp() -> void:
	var root := _make_card("Root", CardData.CardType.ROOT, 1)
	var head := _make_card("Head", CardData.CardType.NORMAL, 2)

	var result := _resolve([root, head], _make_monster("Echo", 5))

	_expect(result.outcome == CombatResultScript.Outcome.RETREAT, "an exhausted chain retreats")
	_expect(result.monster_stats_after.hp == 2, "each resolving card removes its current points from echo HP")
	_expect(head.current_points == 0, "smaller head card spends all its points")
	_expect(root.current_points == 0, "root also spends all points when required")
	_expect(result.depleted_cards.has(head), "depleted normal card is reported to settlement")
	_expect(result.depleted_cards.has(root), "depleted root is reported to settlement")


func _test_equal_points_defeat_echo_and_deplete_card() -> void:
	var root := _make_card("Root", CardData.CardType.ROOT, 1)
	var head := _make_card("Head", CardData.CardType.NORMAL, 3)

	var result := _resolve([root, head], _make_monster("Echo", 3))

	_expect(result.outcome == CombatResultScript.Outcome.VICTORY, "equal points defeat the echo")
	_expect(result.monster_stats_after.hp == 0, "equal points reduce echo HP to zero")
	_expect(head.current_points == 0, "equal comparison depletes the card")
	_expect(result.depleted_cards.has(head), "equal comparison reports the depleted card")
	_expect(root.current_points == 1, "unresolved root is not changed")


func _test_larger_card_keeps_remaining_points_after_victory() -> void:
	var root := _make_card("Root", CardData.CardType.ROOT, 1)
	var head := _make_card("Head", CardData.CardType.NORMAL, 5)

	var result := _resolve([root, head], _make_monster("Echo", 3))

	_expect(result.outcome == CombatResultScript.Outcome.VICTORY, "larger card defeats the echo")
	_expect(head.current_points == 2, "larger card retains unspent points")
	_expect(not result.depleted_cards.has(head), "surviving card is not reported as depleted")


func _test_armor_absorbs_echo_power_before_card_points() -> void:
	var root := _make_card("Root", CardData.CardType.ROOT, 1)
	var head := _make_card("Shielded Head", CardData.CardType.NORMAL, 3, 3)

	var result := _resolve([root, head], _make_monster("Echo", 5))

	_expect(result.outcome == CombatResultScript.Outcome.RETREAT, "nonlethal armored clash retreats")
	_expect(result.monster_stats_after.hp == 1, "root contributes after the armored head clash")
	_expect(head.current_armor == 0, "armor is consumed before points")
	_expect(head.current_points == 1, "only unabsorbed echo power reduces points")
	_expect(not result.depleted_cards.has(head), "card survives when armor leaves positive points")


func _test_depleted_root_is_reported_for_settlement() -> void:
	var root := _make_card("Root", CardData.CardType.ROOT, 2)

	var result := _resolve([root], _make_monster("Echo", 3))

	_expect(result.outcome == CombatResultScript.Outcome.RETREAT, "root-only nonlethal chain retreats")
	_expect(root.current_points == 0, "root can be depleted by a point clash")
	_expect(result.depleted_cards.size() == 1 and result.depleted_cards[0] == root, "settlement receives depleted root")


func _test_regular_echo_actions_do_not_damage_player_or_create_steps() -> void:
	var root := _make_card("Root", CardData.CardType.ROOT, 1)
	var head := _make_card("Head", CardData.CardType.NORMAL, 1)
	var monster := _make_monster("Echo", 5)
	monster.data.actions.append(_make_attack_action(99))
	var player := _make_player_stats(20, 20)

	var result := CombatServiceScript.new().resolve_encounter(player, [root, head], monster)

	_expect(result.player_stats_after.hp == 20, "ordinary point clashes do not damage player HP")
	_expect(result.monster_action_index_after == 0, "ordinary point clashes do not advance echo actions")
	for step in result.steps:
		_expect(step.kind != CombatStepScript.Kind.MONSTER_ACTION, "ordinary point clashes do not create monster-action steps")


func _test_point_clash_trace_only_reports_damage_to_echo() -> void:
	var root := _make_card("Root", CardData.CardType.ROOT, 1)
	var head := _make_card("Head", CardData.CardType.NORMAL, 2, 1)

	var result := _resolve([root, head], _make_monster("Echo", 3))

	_expect(result.steps[0].effects.size() == 1, "one point clash logs one echo-damage effect")
	if not result.steps[0].effects.is_empty():
		var effect := result.steps[0].effects[0]
		_expect(effect.target == CombatEffect.Target.MONSTER, "point clash log targets the echo")
		_expect(effect.value == 2, "point clash log uses the card's pre-clash points")


func _test_retreat_enhancement_increases_echo_health_and_caps() -> void:
	var monster := _make_monster("Strengthening Echo", 5, 2)
	monster.stats.hp = 3
	monster.max_enhancement_stacks = 2

	_expect(monster.gain_enhancement(), "first retreat strengthens the echo")
	_expect(monster.enhancement_stacks == 1, "first retreat records one enhancement stack")
	_expect(monster.stats.max_hp == 7 and monster.stats.hp == 5, "enhancement adds configured max and current HP")
	_expect(monster.gain_enhancement(), "second retreat strengthens the echo")
	_expect(monster.stats.max_hp == 9 and monster.stats.hp == 7, "second enhancement adds health again")
	_expect(not monster.gain_enhancement(), "enhancement stops at its stack cap")
	_expect(monster.stats.max_hp == 9 and monster.stats.hp == 7, "capped enhancement does not change health")


func _resolve(chain: Array[CardInstance], monster: MobInstance) -> CombatResult:
	return CombatServiceScript.new().resolve_encounter(_make_player_stats(20, 20), chain, monster)


func _make_player_stats(max_hp: int, hp: int) -> CombatStats:
	var stats := CombatStatsScript.new()
	stats.max_hp = max_hp
	stats.hp = hp
	stats.attack = 0
	stats.defense = 0
	return stats


func _make_card(name: String, type: CardData.CardType, points: int, armor: int = 0) -> CardInstance:
	var data := CardDataScript.new()
	data.card_name = name
	data.card_type = type
	data.max_points = points
	data.armor = armor
	return CardInstanceScript.new(data)


func _make_monster(name: String, hp: int, enhancement_hp_bonus: int = 1) -> MobInstance:
	var stats_data := CombatStatsDataScript.new()
	stats_data.max_hp = hp
	stats_data.attack = 0
	stats_data.defense = 0
	var data := MobDataScript.new()
	data.mob_name = name
	data.base_stats = stats_data
	data.enhancement_hp_bonus = enhancement_hp_bonus
	return data.create_instance()


func _make_attack_action(value: int) -> MobAction:
	var action := MobAction.new()
	action.value = value
	return action


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)