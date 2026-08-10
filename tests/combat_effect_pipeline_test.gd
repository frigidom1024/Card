extends SceneTree

const CombatEffectScript = preload("res://scripts/combatv2/card/combat_effect.gd")
const CombatEffectDraftScript = preload("res://scripts/combatv2/combat_effect_draft.gd")
const CombatEffectResolverScript = preload("res://scripts/combatv2/combat_effect_resolver.gd")
const CombatServiceScript = preload("res://scripts/combatv2/combat_service.gd")
const CombatContextScript = preload("res://scripts/combatv2/combat_context.gd")
const CombatStatsScript = preload("res://scripts/combatv2/combat_stats.gd")
const CombatStatsDataScript = preload("res://scripts/combatv2/combat_stats_data.gd")
const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const MobDataScript = preload("res://scripts/game/event/encounter/mob_data.gd")
const ShieldBreakScript = preload("res://scripts/combatv2/mob_effects/mob_effect_shield_break.gd")
const RearShockScript = preload("res://scripts/combatv2/mob_effects/mob_effect_rear_shock.gd")
const CardDamageMultiplierRuleScript = preload("res://scripts/combatv2/card/rules/card_damage_multiplier_rule.gd")

var _failure_count = 0

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_effect_can_target_a_card_and_carry_metadata()
	_test_resolver_applies_card_armor_before_points()
	_test_cancelled_effect_is_not_applied()
	_test_card_rule_modifies_outgoing_effect_and_consumes_uses()
	_test_shield_break_mob_effect_modifies_damage_effect()
	_test_rear_shock_mob_effect_adds_damage_to_cards_behind_head()
	_test_combat_steps_contain_all_resolved_effects()
	_test_effect_resolver_records_before_after_snapshots()
	_test_mob_effect_effective_count_limits_successful_hooks()
	_test_draft_assigns_stable_phase_sequence_and_card_target_name()
	_test_heal_effect_records_before_after_snapshots()
	_test_damage_records_defense_absorption_for_stats_targets()
	_test_invalid_effect_target_is_not_marked_resolved()
	quit(1 if _failure_count > 0 else 0)

func _test_effect_can_target_a_card_and_carry_metadata() -> void:
	var card = _make_card("目标卡", CardData.CardType.NORMAL, 3, 2)
	var effect = CombatEffectScript.new(
		CombatEffectScript.Type.DAMAGE,
		CombatEffectScript.Target.CARD,
		4,
		CombatEffectScript.SourceType.MONSTER_ACTION,
		"测试残响",
		card,
		{"armor_multiplier": 2},
		["monster_attack", "shield_break"]
	)
	_expect(effect.target_card == card, "effect can point to a concrete card")
	_expect(effect.get_parameter("armor_multiplier", 0) == 2, "effect preserves parameters")
	_expect(effect.tags.has("shield_break"), "effect preserves tags")

func _test_resolver_applies_card_armor_before_points() -> void:
	var card = _make_card("护甲卡", CardData.CardType.NORMAL, 5, 2)
	var monster = _make_monster("残响", 5)
	var context = CombatContextScript.new(_make_stats(), monster, [card])
	var draft = CombatEffectDraftScript.new(context, card)
	draft.add_effect(CombatEffectScript.new(
		CombatEffectScript.Type.DAMAGE,
		CombatEffectScript.Target.CARD,
		3,
		CombatEffectScript.SourceType.MONSTER_ACTION,
		"残响攻击",
		card
	))
	var resolved = CombatEffectResolverScript.new().resolve(draft)
	_expect(card.current_armor == 0, "card armor is consumed first")
	_expect(card.current_points == 4, "only damage beyond armor consumes points")
	_expect(resolved.size() == 1, "resolver returns the resolved effect")
	if not resolved.is_empty():
		_expect(resolved[0].get_parameter("absorbed", 0) == 2, "resolver records absorbed damage")
		_expect(resolved[0].get_parameter("applied", 0) == 1, "resolver records applied point damage")

func _test_cancelled_effect_is_not_applied() -> void:
	var monster = _make_monster("残响", 5)
	var context = CombatContextScript.new(_make_stats(), monster, [])
	var effect = CombatEffectScript.new(
		CombatEffectScript.Type.DAMAGE,
		CombatEffectScript.Target.MONSTER,
		3,
		CombatEffectScript.SourceType.PLAYER_CARD,
		"卡牌"
	)
	effect.cancelled = true
	var draft = CombatEffectDraftScript.new(context, null)
	draft.add_effect(effect)
	var resolved = CombatEffectResolverScript.new().resolve(draft)
	_expect(monster.stats.hp == 5, "cancelled effect does not mutate target")
	_expect(resolved.size() == 1 and resolved[0].cancelled, "cancelled effect remains in the combat log")

func _test_card_rule_modifies_outgoing_effect_and_consumes_uses() -> void:
	var root := _make_card("倍率根", CardData.CardType.ROOT, 1)
	var rule := CardDamageMultiplierRuleScript.new()
	rule.multiplier = 2
	rule.effective_count = 1
	root.card_data.effect_rules.append(rule)
	var result := CombatServiceScript.new().resolve_encounter(_make_stats(), [root], _make_monster("残响", 2))
	_expect(result.outcome == CombatResult.Outcome.VICTORY, "card rule can alter the outgoing CombatEffect")
	_expect(root.get_rule_trigger_count(0) == 1, "successful combat rule consumes one effective use")
	if result.steps.size() == 1:
		_expect(result.steps[0].effects[0].value == 2, "logged outgoing effect contains modified damage")


func _test_shield_break_mob_effect_modifies_damage_effect() -> void:
	var root = _make_card("根", CardData.CardType.ROOT, 1, 2)
	var monster = _make_monster("破盾残响", 1)
	var effect = ShieldBreakScript.new()
	effect.armor_multiplier = 2
	monster.data.effects.append(effect)
	var result = CombatServiceScript.new().resolve_encounter(_make_stats(), [root], monster)
	_expect(result.outcome == CombatResult.Outcome.VICTORY, "shield break echo can be defeated")
	_expect(root.current_armor == 0, "shield break effect doubles damage to armor")
	_expect(root.current_points == 1, "shield break consumes armor without bypassing its blocked damage")

func _test_rear_shock_mob_effect_adds_damage_to_cards_behind_head() -> void:
	var root = _make_card("根", CardData.CardType.ROOT, 2)
	var middle = _make_card("中段", CardData.CardType.NORMAL, 2)
	var head = _make_card("头部", CardData.CardType.NORMAL, 1)
	var monster = _make_monster("后排冲击残响", 1)
	var effect = RearShockScript.new()
	effect.damage = 1
	effect.card_count = 1
	monster.data.effects.append(effect)
	var result = CombatServiceScript.new().resolve_encounter(_make_stats(), [root, middle, head], monster)
	var found = false
	for step in result.steps:
		for logged_effect in step.effects:
			if logged_effect.target == CombatEffect.Target.CARD and logged_effect.target_card != head:
				found = true
	_expect(found, "rear shock adds a card-targeted damage effect")
	_expect(middle.current_points == 1, "rear shock damages a card behind the head")

func _test_combat_steps_contain_all_resolved_effects() -> void:
	var root = _make_card("根", CardData.CardType.ROOT, 1)
	var monster = _make_monster("残响", 3)
	var result = CombatServiceScript.new().resolve_encounter(_make_stats(), [root], monster)
	_expect(result.steps.size() == 1, "one-card clash creates one step")
	if result.steps.size() == 1:
		_expect(result.steps[0].effects.size() == 2, "step logs both card attack and monster retaliation")
		var has_card_damage = false
		for effect in result.steps[0].effects:
			if effect.target == CombatEffect.Target.CARD:
				has_card_damage = true
		_expect(has_card_damage, "step exposes retaliation as a CombatEffect")

func _make_stats() -> CombatStats:
	var stats = CombatStatsScript.new()
	stats.max_hp = 20
	stats.hp = 20
	stats.attack = 0
	stats.defense = 0
	return stats

func _make_card(name: String, type: CardData.CardType, points: int, armor: int = 0) -> CardInstance:
	var data = CardDataScript.new()
	data.card_name = name
	data.card_type = type
	data.max_points = points
	data.armor = armor
	return CardInstanceScript.new(data)

func _make_monster(name: String, hp: int) -> MobInstance:
	var stats_data = CombatStatsDataScript.new()
	stats_data.max_hp = hp
	stats_data.attack = 0
	stats_data.defense = 0
	var data = MobDataScript.new()
	data.mob_name = name
	data.base_stats = stats_data
	return data.create_instance()


func _test_damage_records_defense_absorption_for_stats_targets() -> void:
	var player := _make_stats()
	player.defense = 2
	var context := CombatContextScript.new(player, _make_monster("护甲残响", 5), [])
	var draft := CombatEffectDraftScript.new(context, null)
	draft.add_effect(CombatEffectScript.new(
		CombatEffectScript.Type.DAMAGE,
		CombatEffectScript.Target.PLAYER,
		5,
		CombatEffectScript.SourceType.MONSTER_ACTION,
		"残响攻击"
	))
	var resolved := CombatEffectResolverScript.new().resolve(draft)
	if not resolved.is_empty():
		var effect: CombatEffect = resolved[0]
		_expect(effect.get_parameter("absorbed", -1) == 2, "stats damage records defense absorption")
		_expect(effect.get_parameter("applied", -1) == 3, "stats damage records hp damage after defense")
		_expect(effect.get_parameter("total", -1) == 5, "stats damage records total incoming damage")


func _test_invalid_effect_target_is_not_marked_resolved() -> void:
	var draft := CombatEffectDraftScript.new(null, null)
	var effect := draft.add_effect(CombatEffectScript.new(
		CombatEffectScript.Type.DAMAGE,
		CombatEffectScript.Target.PLAYER,
		3,
		CombatEffectScript.SourceType.SYSTEM,
		"无效目标测试"
	))
	var resolved := CombatEffectResolverScript.new().resolve(draft)
	_expect(resolved.size() == 1, "invalid effects remain in the log")
	_expect(effect.get_parameter("resolved", true) == false, "invalid effects are marked unresolved")
	_expect(effect.get_parameter("applied", -1) == 0, "invalid effects record zero applied value")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)


func _test_effect_resolver_records_before_after_snapshots() -> void:
	var card := _make_card("快照卡", CardData.CardType.NORMAL, 4, 2)
	var monster := _make_monster("快照残响", 6)
	var context := CombatContextScript.new(_make_stats(), monster, [card])
	var draft := CombatEffectDraftScript.new(context, card)
	draft.add_effect(CombatEffectScript.new(
		CombatEffectScript.Type.DAMAGE,
		CombatEffectScript.Target.CARD,
		3,
		CombatEffectScript.SourceType.MONSTER_ACTION,
		"快照攻击",
		card
	))
	var resolved := CombatEffectResolverScript.new().resolve(draft)
	if not resolved.is_empty():
		_expect(resolved[0].get_parameter("card_armor_before", -1) == 2, "card damage records armor before")
		_expect(resolved[0].get_parameter("card_armor_after", -1) == 0, "card damage records armor after")
		_expect(resolved[0].get_parameter("card_points_before", -1) == 4, "card damage records points before")
		_expect(resolved[0].get_parameter("card_points_after", -1) == 3, "card damage records points after")


func _test_mob_effect_effective_count_limits_successful_hooks() -> void:
	var root := _make_card("限次根", CardData.CardType.ROOT, 2, 10)
	var monster := _make_monster("限次残响", 3)
	var shield_break := ShieldBreakScript.new()
	shield_break.armor_multiplier = 2
	shield_break.effective_count = 1
	monster.data.effects.append(shield_break)
	var result := CombatServiceScript.new().resolve_encounter(_make_stats(), [root], monster)
	var tagged_count := 0
	for step in result.steps:
		for effect in step.effects:
			if effect != null and effect.tags.has("shield_break"):
				tagged_count += 1
	_expect(tagged_count == 1, "mob effect effective_count limits successful hook executions")


func _test_draft_assigns_stable_phase_sequence_and_card_target_name() -> void:
	var card := _make_card("命名目标", CardData.CardType.NORMAL, 2)
	var draft := CombatEffectDraftScript.new(null, card)
	draft.phase = "before_resolve"
	var effect := draft.add_damage(
		CombatEffectScript.Target.CARD,
		1,
		CombatEffectScript.SourceType.MONSTER_EFFECT,
		"测试效果",
		card
	)
	_expect(effect.sequence == 0, "draft assigns a deterministic effect sequence")
	_expect(effect.phase == "before_resolve", "draft records the hook phase on created effects")
	_expect(effect.target_name == "命名目标", "card-targeted effect snapshots its target name")


func _test_heal_effect_records_before_after_snapshots() -> void:
	var player := _make_stats()
	player.hp = 12
	var context := CombatContextScript.new(player, _make_monster("治疗残响", 5), [])
	var draft := CombatEffectDraftScript.new(context, null)
	draft.add_effect(CombatEffectScript.new(
		CombatEffectScript.Type.HEAL,
		CombatEffectScript.Target.PLAYER,
		3,
		CombatEffectScript.SourceType.SYSTEM,
		"治疗测试"
	))
	var resolved := CombatEffectResolverScript.new().resolve(draft)
	if not resolved.is_empty():
		_expect(resolved[0].get_parameter("hp_before", -1) == 12, "heal records target hp before")
		_expect(resolved[0].get_parameter("hp_after", -1) == 15, "heal records target hp after")
