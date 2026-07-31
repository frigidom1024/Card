extends SceneTree

const CombatEffectScript = preload("res://scripts/combat/combat_effect.gd")
const CombatServiceScript = preload("res://scripts/combat/combat_service.gd")
const MobActionResolverScript = preload("res://scripts/combat/mob_action_resolver.gd")
const MobActionScript = preload("res://scripts/game/event/mob_action.gd")
const CombatPenaltyScript = preload("res://scripts/combat/combat_penalty.gd")
const CombatResultScript = preload("res://scripts/combat/combat_result.gd")
const CombatStateScript = preload("res://scripts/combat/combat_state.gd")
const CombatStatsScript = preload("res://scripts/combat/combat_stats.gd")
const CombatStepScript = preload("res://scripts/combat/combat_step.gd")
const MobDataScript = preload("res://scripts/game/event/mob_data.gd")
const CombatStatsDataScript = preload("res://scripts/combat/combat_stats_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardConditionScript = preload("res://scripts/combat/card_condition.gd")
const CardResolutionContextScript = preload("res://scripts/combat/card_resolution_context.gd")
const CardResolutionDraftScript = preload("res://scripts/combat/card_resolution_draft.gd")
const ChainRuleScript = preload("res://scripts/combat/chain_rule.gd")
const ChainRuleTrackerScript = preload("res://scripts/combat/chain_rule_tracker.gd")
const WeaponComboRootRuleProviderScript = preload(
	"res://scripts/combat/root_rules/weapon_combo_root_rule_provider.gd"
)
const CardRuleScript = preload("res://scripts/combat/card_rule.gd")
const PreviousCardHasTagConditionScript = preload(
	"res://scripts/combat/conditions/previous_card_has_tag_condition.gd"
)
const PreviousCardHasTypeConditionScript = preload(
	"res://scripts/combat/conditions/previous_card_has_type_condition.gd"
)
const HasResolvedCardWithTagConditionScript = preload(
	"res://scripts/combat/conditions/has_resolved_card_with_tag_condition.gd"
)
const ResolvedCardCountConditionScript = preload(
	"res://scripts/combat/conditions/resolved_card_count_condition.gd"
)
const PlayerHpRatioConditionScript = preload(
	"res://scripts/combat/conditions/player_hp_ratio_condition.gd"
)
const MonsterHpRatioConditionScript = preload(
	"res://scripts/combat/conditions/monster_hp_ratio_condition.gd"
)
const IsFirstCardConditionScript = preload(
	"res://scripts/combat/conditions/is_first_card_condition.gd"
)
const IsLastCardConditionScript = preload(
	"res://scripts/combat/conditions/is_last_card_condition.gd"
)
const AddDamageOperationScript = preload("res://scripts/combat/operations/add_damage_operation.gd")
const MultiplyDamageOperationScript = preload(
	"res://scripts/combat/operations/multiply_damage_operation.gd"
)
const AddDefenseOperationScript = preload(
	"res://scripts/combat/operations/add_defense_operation.gd"
)
const AddHealOperationScript = preload("res://scripts/combat/operations/add_heal_operation.gd")
const AddCombatEffectOperationScript = preload(
	"res://scripts/combat/operations/add_combat_effect_operation.gd"
)

var _failure_count := 0


func _init() -> void:
	_test_combat_effect()
	_test_mob_action_resolver()
	_test_combat_stats_runtime_copy()
	_test_combat_penalty()
	_test_combat_step_snapshots()
	_test_combat_result_ownership()
	_test_combat_state_foundation()
	_test_existing_card_resource_stays_loadable()
	_test_card_effect_rules_use_pre_card_snapshot_and_ordered_draft()
	_test_root_chain_rule_batches()
	_test_chain_rule_context_snapshot()
	_test_service_attack_card_then_monster_action()
	_test_service_lethal_card_wins_without_monster_action()
	_test_service_root_resolves_registers_rules_without_action()
	_test_service_adjacent_weapons_share_one_monster_action()
	_test_service_non_adjacent_weapons_receive_one_action_per_card()
	_test_service_low_hp_rule_uses_pre_card_context()
	_test_service_retreat_adds_tail_penalty()
	_test_service_monster_attack_defeats_immediately()
	_test_service_steps_are_ordered_and_isolated()
	_test_service_input_monster_remains_unchanged()
	_test_service_root_to_weapon_flushes_before_retreat()
	_test_service_null_monster_action_records_empty_step()
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


func _test_mob_action_resolver() -> void:
	var attack := MobActionScript.new()
	attack.type = MobActionScript.Type.ATTACK
	attack.value = 4
	var attack_effects := MobActionResolverScript.to_effects(attack, "Test Mob")
	_expect(attack_effects.size() == 1, "attack action emits one effect")
	if attack_effects.size() == 1:
		var attack_effect: CombatEffect = attack_effects[0]
		_expect(attack_effect.type == CombatEffectScript.Type.DAMAGE, "attack maps to damage")
		_expect(attack_effect.target == CombatEffectScript.Target.PLAYER, "attack targets player")
		_expect(attack_effect.value == 4, "attack preserves its configured value")
		_expect(
			attack_effect.source_type == CombatEffectScript.SourceType.MONSTER_ACTION,
			"attack effects identify the monster-action source"
		)
		_expect(attack_effect.source_name == "Test Mob", "attack effects preserve the source name")

	var defend := MobActionScript.new()
	defend.type = MobActionScript.Type.DEFEND
	defend.value = 2
	var defend_effects := MobActionResolverScript.to_effects(defend, "Test Mob")
	_expect(defend_effects.size() == 1, "defend action emits one effect")
	if defend_effects.size() == 1:
		var defend_effect: CombatEffect = defend_effects[0]
		_expect(
			defend_effect.type == CombatEffectScript.Type.ADD_DEFENSE, "defend maps to add defense"
		)
		_expect(defend_effect.target == CombatEffectScript.Target.MONSTER, "defend targets monster")

	var heal := MobActionScript.new()
	heal.type = MobActionScript.Type.HEAL
	heal.value = -2
	var heal_effects := MobActionResolverScript.to_effects(heal, "Test Mob")
	_expect(heal_effects.size() == 1, "heal action emits one effect")
	if heal_effects.size() == 1:
		var heal_effect: CombatEffect = heal_effects[0]
		_expect(heal_effect.type == CombatEffectScript.Type.HEAL, "heal maps to heal")
		_expect(heal_effect.target == CombatEffectScript.Target.MONSTER, "heal targets monster")
		_expect(heal_effect.value == 0, "heal delegates negative-value clamping to combat effects")

	for unsupported_type in [
		MobActionScript.Type.BUFF,
		MobActionScript.Type.DEBUFF,
		MobActionScript.Type.SPECIAL,
	]:
		var unsupported := MobActionScript.new()
		unsupported.type = unsupported_type
		_expect(
			MobActionResolverScript.to_effects(unsupported, "Test Mob").is_empty(),
			"unsupported demo action types produce no effects"
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


func _test_existing_card_resource_stays_loadable() -> void:
	for file_name in DirAccess.get_files_at("res://data/cards"):
		if file_name.ends_with(".tres"):
			var card := load("res://data/cards/%s" % file_name) as CardData
			_expect(card != null, "existing card loads: %s" % file_name)

	var legacy := load("res://data/cards/AllThingsRevival.tres") as CardData
	_expect(legacy != null, "legacy card loads")
	if legacy != null:
		_expect(legacy.effect_rules.is_empty(), "legacy card defaults to no rules")
		_expect(
			CardResolutionDraftScript.from_card(legacy).heal == legacy.heal,
			"legacy base heal is preserved"
		)

	var root := load("res://tests/fixtures/cards/weapon_combo_root.tres") as CardData
	_expect(root != null, "combo root fixture loads")
	if root != null:
		_expect(root.root_rule_providers.size() == 1, "combo root has one provider")
		if root.root_rule_providers.size() == 1:
			_expect(
				root.root_rule_providers[0] is WeaponComboRootRuleProvider,
				"combo root loads a weapon-combo provider"
			)


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


func _test_card_effect_rules_use_pre_card_snapshot_and_ordered_draft() -> void:
	var previous_data := CardDataScript.new()
	previous_data.card_type = CardDataScript.CardType.ROOT
	previous_data.tags = [CardDataScript.CardTag.WEAPON]
	var current_data := CardDataScript.new()
	current_data.card_name = "Test Card"
	current_data.damage = 5
	var last_data := CardDataScript.new()
	var previous_card := CardInstanceScript.new(previous_data)
	var current_card := CardInstanceScript.new(current_data)
	var last_card := CardInstanceScript.new(last_data)
	var cards: Array[CardInstance] = [previous_card, current_card, last_card]
	var player_stats := _make_stats(20, 8, 5, 3)
	var monster_data := MobDataScript.new()
	monster_data.base_stats = CombatStatsDataScript.new()
	monster_data.base_stats.max_hp = 16
	monster_data.base_stats.attack = 4
	monster_data.base_stats.defense = 2
	var monster := monster_data.create_instance()
	monster.stats.hp = 4
	var state := CombatStateScript.new(player_stats, monster, cards)
	state.resolved_cards = [previous_card]
	var remaining_cards: Array[CardInstance] = [current_card, last_card]
	state.remaining_cards = remaining_cards

	var context := CardResolutionContextScript.new(state, current_card, 1)
	var first_context := CardResolutionContextScript.new(state, previous_card, 0)
	var last_context := CardResolutionContextScript.new(state, last_card, 2)
	player_stats.hp = 1
	player_stats.defense = 0
	state.monster.stats.hp = 15
	state.monster.stats.defense = 0
	state.resolved_cards.clear()
	state.remaining_cards.clear()
	state.cards.clear()

	_expect(
		context.get_player_hp() == 8 and context.get_player_defense() == 3,
		"card resolution context keeps pre-card player values"
	)
	_expect(
		context.get_monster_hp() == 4 and context.get_monster_defense() == 2,
		"card resolution context keeps pre-card monster values"
	)
	_expect(
		(
			context.get_previous_resolved_card() != previous_card
			and (
				context.get_previous_resolved_card().card_data.card_type
				== CardDataScript.CardType.ROOT
			)
		),
		"card resolution context exposes an isolated previous-card snapshot"
	)
	var exposed_current_card := context.get_current_card()
	exposed_current_card.card_data.damage = 99
	_expect(
		context.get_current_card().card_data.damage == 5,
		"card resolution context returns read-only card snapshots"
	)

	_expect(
		context.get_resolved_cards().size() == 1 and context.get_remaining_cards().size() == 2,
		"card resolution context keeps resolution history and remaining cards"
	)

	var previous_tag_condition := PreviousCardHasTagConditionScript.new()
	previous_tag_condition.required_tag = CardDataScript.CardTag.WEAPON
	var previous_type_condition := PreviousCardHasTypeConditionScript.new()
	previous_type_condition.required_type = CardDataScript.CardType.ROOT
	var history_tag_condition := HasResolvedCardWithTagConditionScript.new()
	history_tag_condition.required_tag = CardDataScript.CardTag.WEAPON
	_expect(previous_tag_condition.evaluate(context), "previous-tag condition reads the snapshot")
	_expect(previous_type_condition.evaluate(context), "previous-type condition reads the snapshot")
	_expect(
		history_tag_condition.evaluate(context), "resolved-history condition reads the snapshot"
	)

	var count_condition := ResolvedCardCountConditionScript.new()
	count_condition.expected_count = 1
	count_condition.comparison = CardConditionScript.Comparison.EQUAL
	_expect(count_condition.evaluate(context), "resolved-card count supports equality")
	count_condition.expected_count = 0
	count_condition.comparison = CardConditionScript.Comparison.GREATER_THAN
	_expect(count_condition.evaluate(context), "resolved-card count supports greater-than")
	count_condition.expected_count = 1
	count_condition.comparison = CardConditionScript.Comparison.GREATER_OR_EQUAL
	_expect(count_condition.evaluate(context), "resolved-card count supports greater-or-equal")
	count_condition.expected_count = 2
	count_condition.comparison = CardConditionScript.Comparison.LESS_THAN
	_expect(count_condition.evaluate(context), "resolved-card count supports less-than")
	count_condition.expected_count = 1
	count_condition.comparison = CardConditionScript.Comparison.LESS_OR_EQUAL
	_expect(count_condition.evaluate(context), "resolved-card count supports less-or-equal")

	var player_hp_condition := PlayerHpRatioConditionScript.new()
	player_hp_condition.threshold = 0.5
	player_hp_condition.comparison = CardConditionScript.Comparison.LESS_THAN
	var monster_hp_condition := MonsterHpRatioConditionScript.new()
	monster_hp_condition.threshold = 0.5
	monster_hp_condition.comparison = CardConditionScript.Comparison.LESS_THAN
	_expect(player_hp_condition.evaluate(context), "player HP-ratio condition reads pre-card HP")
	_expect(monster_hp_condition.evaluate(context), "monster HP-ratio condition reads pre-card HP")
	_expect(
		IsFirstCardConditionScript.new().evaluate(first_context),
		"first-card condition uses the full chain position"
	)
	_expect(
		not IsFirstCardConditionScript.new().evaluate(context), "middle card is not the first card"
	)
	_expect(
		IsLastCardConditionScript.new().evaluate(last_context),
		"last-card condition uses the full chain position"
	)
	_expect(
		not IsLastCardConditionScript.new().evaluate(context), "middle card is not the last card"
	)

	var double_damage := MultiplyDamageOperationScript.new()
	double_damage.multiplier = 2.0
	var weapon_rule := CardRuleScript.new()
	weapon_rule.condition = previous_tag_condition
	weapon_rule.operation = double_damage
	var weapon_draft := CardResolutionDraftScript.from_card(current_data)
	weapon_rule.apply(context, weapon_draft)
	var weapon_effects := weapon_draft.to_effects(
		CombatEffectScript.SourceType.PLAYER_CARD, "Test Card"
	)
	_expect(weapon_effects.size() == 1, "damage-only draft emits one effect")
	_expect(weapon_effects[0].value == 10, "previous weapon rule doubles current damage")

	var effect_data := CardDataScript.new()
	effect_data.damage = 5
	effect_data.defense = 2
	effect_data.heal = 1
	var effect_draft := CardResolutionDraftScript.from_card(effect_data)
	var add_damage := AddDamageOperationScript.new()
	add_damage.amount = 3
	var add_damage_rule := CardRuleScript.new()
	add_damage_rule.operation = add_damage
	add_damage_rule.apply(context, effect_draft)
	var non_matching_type := PreviousCardHasTypeConditionScript.new()
	non_matching_type.required_type = CardDataScript.CardType.NORMAL
	var blocked_operation := AddDamageOperationScript.new()
	blocked_operation.amount = 99
	var blocked_rule := CardRuleScript.new()
	blocked_rule.condition = non_matching_type
	blocked_rule.operation = blocked_operation
	blocked_rule.apply(context, effect_draft)
	double_damage.apply(context, effect_draft)
	var add_defense := AddDefenseOperationScript.new()
	add_defense.amount = 2
	add_defense.apply(context, effect_draft)
	var add_heal := AddHealOperationScript.new()
	add_heal.amount = 3
	var low_hp_heal_rule := CardRuleScript.new()
	low_hp_heal_rule.condition = player_hp_condition
	low_hp_heal_rule.operation = add_heal
	low_hp_heal_rule.apply(context, effect_draft)
	var extra_effect := AddCombatEffectOperationScript.new()
	extra_effect.effect_type = CombatEffectScript.Type.DAMAGE
	extra_effect.target = CombatEffectScript.Target.MONSTER
	extra_effect.value = 7
	extra_effect.apply(context, effect_draft)
	var effects := effect_draft.to_effects(CombatEffectScript.SourceType.PLAYER_CARD, "Test Card")
	_expect(effects.size() == 4, "draft emits base effects plus extra effects")
	_expect(
		(
			effects[0].type == CombatEffectScript.Type.DAMAGE
			and effects[0].target == CombatEffectScript.Target.MONSTER
			and effects[0].value == 16
		),
		"damage operations update only the current draft"
	)
	_expect(
		(
			effects[1].type == CombatEffectScript.Type.ADD_DEFENSE
			and effects[1].target == CombatEffectScript.Target.PLAYER
			and effects[1].value == 4
		),
		"draft emits defense after damage"
	)
	_expect(
		(
			effects[2].type == CombatEffectScript.Type.HEAL
			and effects[2].target == CombatEffectScript.Target.PLAYER
			and effects[2].value == 4
		),
		"low-HP healing and base healing are emitted after defense"
	)
	_expect(
		(
			effects[3].type == CombatEffectScript.Type.DAMAGE
			and effects[3].target == CombatEffectScript.Target.MONSTER
			and effects[3].value == 7
			and effects[3].source_name == "Test Card"
		),
		"extra effects append in operation order with card source metadata"
	)
	_expect(
		player_stats.hp == 1 and state.monster.stats.hp == 15,
		"conditions and operations never mutate combat state"
	)

	var clamped_draft := CardResolutionDraftScript.from_card(current_data)
	var negative_damage := AddDamageOperationScript.new()
	negative_damage.amount = -99
	negative_damage.apply(context, clamped_draft)
	_expect(
		clamped_draft.to_effects(CombatEffectScript.SourceType.PLAYER_CARD, "Test Card").is_empty(),
		"negative draft additions clamp base effects at zero"
	)


func _test_root_chain_rule_batches() -> void:
	var root_data := CardDataScript.new()
	root_data.card_type = CardDataScript.CardType.ROOT
	root_data.card_name = "Test Combo Root"
	var provider := WeaponComboRootRuleProviderScript.new()
	root_data.root_rule_providers = [provider]
	var root_card := CardInstanceScript.new(root_data)
	var root_context := CardResolutionContextScript.new(null, root_card, 0)
	var rules := provider.build_rules(root_context)
	_expect(root_data.root_rule_providers.size() == 1, "root cards expose typed rule providers")
	_expect(rules.size() == 1, "root registration creates one combo rule without an action")
	if rules.is_empty():
		return
	_expect(
		(
			rules[0].rule_id == &"weapon_combo"
			and rules[0].required_tag == CardDataScript.CardTag.WEAPON
		),
		"weapon combo provider creates the configured weapon rule"
	)

	var first_weapon := _make_card_with_tag(CardDataScript.CardTag.WEAPON)
	var second_weapon := _make_card_with_tag(CardDataScript.CardTag.WEAPON)
	var heal := _make_card_with_tag(CardDataScript.CardTag.HEAL)
	var tracker := ChainRuleTrackerScript.new()
	tracker.start(rules)
	_expect(not tracker.begin_card(first_weapon), "first adjacent weapon starts a player batch")
	_expect(
		not tracker.finish_card(first_weapon), "first adjacent weapon defers the monster action"
	)
	_expect(not tracker.begin_card(second_weapon), "second adjacent weapon stays in the same batch")
	_expect(tracker.finish_card(second_weapon), "two adjacent weapons close one player batch")
	_expect(not tracker.begin_card(heal), "completed combo does not add a pre-heal monster action")
	_expect(tracker.finish_card(heal), "heal receives its own monster action after the combo")
	_expect(not tracker.flush_pending(), "completed combo chain leaves no extra pending action")

	tracker.start(provider.build_rules(root_context))
	_expect(
		not tracker.begin_card(first_weapon), "first non-adjacent weapon sequence starts pending"
	)
	_expect(not tracker.finish_card(first_weapon), "first non-adjacent weapon defers its action")
	_expect(tracker.begin_card(heal), "nonmatching heal closes the pending weapon batch first")
	_expect(tracker.finish_card(heal), "heal then closes its own ordinary batch")
	_expect(
		not tracker.begin_card(second_weapon),
		"later weapon starts a new batch instead of combining"
	)
	_expect(not tracker.finish_card(second_weapon), "later lone weapon stays pending for flush")
	_expect(tracker.flush_pending(), "end-of-chain flush closes a lone final weapon batch")

	tracker.start(provider.build_rules(root_context))
	_expect(not tracker.begin_card(first_weapon), "single weapon begins an incomplete batch")
	_expect(
		not tracker.finish_card(first_weapon),
		"single weapon does not act before end-of-chain flush"
	)
	_expect(tracker.flush_pending(), "root then weapon flushes the pending batch")
	_expect(not tracker.flush_pending(), "flushing a closed batch does not request another action")

	tracker.start([])
	_expect(not tracker.begin_card(heal), "ordinary cards have no pre-action without chain rules")
	_expect(tracker.finish_card(heal), "ordinary cards close their own batch without chain rules")
	_expect(
		not tracker.flush_pending(), "ordinary cards leave no pending batch without chain rules"
	)

	var duplicate_rule := ChainRuleScript.new(
		&"weapon_combo", CardDataScript.CardTag.WEAPON, 3, "Duplicate Combo Root"
	)
	tracker.start([rules[0], duplicate_rule])
	_expect(not tracker.begin_card(first_weapon), "first rule type begins its combo batch")
	_expect(
		not tracker.finish_card(first_weapon),
		"first combo card stays pending with duplicate rule data"
	)
	_expect(not tracker.begin_card(second_weapon), "second combo card remains adjacent")
	_expect(
		tracker.finish_card(second_weapon),
		"tracker keeps the first matching root rule type instead of stacking duplicates"
	)


func _test_chain_rule_context_snapshot() -> void:
	var rule := ChainRuleScript.new(
		&"weapon_combo", CardDataScript.CardTag.WEAPON, 2, "Snapshot Root"
	)
	var current_card := _make_card_with_tag(CardDataScript.CardTag.WEAPON)
	var state := CombatStateScript.new(_make_stats(10, 10, 0, 0), null, [current_card])
	state.active_chain_rules = [rule]
	state.current_batch_id = 7
	state.current_batch_card_count = 1
	var context := CardResolutionContextScript.new(state, current_card, 0)

	rule.rule_id = &"mutated_rule"
	state.current_batch_id = 99
	state.current_batch_card_count = 99
	state.active_chain_rules.clear()
	var exposed_rule_ids := context.get_active_chain_rule_ids()
	exposed_rule_ids.clear()

	_expect(
		context.get_active_chain_rule_ids() == [&"weapon_combo"],
		"card context copies rule IDs without exposing mutable chain rules"
	)
	_expect(
		context.get_current_batch_id() == 7 and context.get_current_batch_card_count() == 1,
		"card context snapshots current batch scalars"
	)


func _test_service_attack_card_then_monster_action() -> void:
	var player := _make_stats(10, 10, 0, 0)
	var root := _make_card(CardDataScript.CardType.ROOT, "Root")
	var attack := _make_card(CardDataScript.CardType.NORMAL, "Strike", 3)
	var result := CombatServiceScript.new().resolve_encounter(
		player, [root, attack], _make_mob("Wolf", 10, 0, [_make_action(MobActionScript.Type.ATTACK, 2)])
	)

	_expect(result.outcome == CombatResultScript.Outcome.RETREAT, "nonlethal attack exhausts into retreat")
	_expect(result.monster_stats_after.hp == 7, "attack card reduces monster HP")
	_expect(result.player_stats_after.hp == 8, "nonlethal attack receives one monster action")
	_expect(result.steps.size() == 3, "root, player card, and monster action each record a step")
	if result.steps.size() == 3:
		_expect(result.steps[1].kind == CombatStepScript.Kind.PLAYER_CARD, "attack is a player-card step")
		_expect(result.steps[2].kind == CombatStepScript.Kind.MONSTER_ACTION, "attack is followed by monster step")


func _test_service_lethal_card_wins_without_monster_action() -> void:
	var root := _make_card(CardDataScript.CardType.ROOT, "Root")
	var lethal := _make_card(CardDataScript.CardType.NORMAL, "Lethal", 10)
	var result := CombatServiceScript.new().resolve_encounter(
		_make_stats(10, 10, 0, 0),
		[root, lethal],
		_make_mob("Wolf", 10, 0, [_make_action(MobActionScript.Type.ATTACK, 9)])
	)

	_expect(result.outcome == CombatResultScript.Outcome.VICTORY, "lethal card wins")
	_expect(result.steps.size() == 2, "lethal card has no monster response step")
	_expect(result.penalties.is_empty(), "victory has no retreat penalty")


func _test_service_root_resolves_registers_rules_without_action() -> void:
	var provider := WeaponComboRootRuleProviderScript.new()
	var root := _make_card(CardDataScript.CardType.ROOT, "Guard Root", 0, 4)
	root.card_data.root_rule_providers = [provider]
	var result := CombatServiceScript.new().resolve_encounter(
		_make_stats(10, 10, 0, 0),
		[root],
		_make_mob("Wolf", 10, 0, [_make_action(MobActionScript.Type.ATTACK, 3)])
	)

	_expect(result.player_stats_after.defense == 4, "root resolves its own defense")
	_expect(result.steps.size() == 1, "root never triggers a monster action")
	_expect(result.steps[0].kind == CombatStepScript.Kind.ROOT_CARD, "root uses a root-card step")


func _test_service_adjacent_weapons_share_one_monster_action() -> void:
	var root := _make_combo_root()
	var first_weapon := _make_card(
		CardDataScript.CardType.NORMAL, "First Weapon", 1, 0, 0, [CardDataScript.CardTag.WEAPON]
	)
	var second_weapon := _make_card(
		CardDataScript.CardType.NORMAL, "Second Weapon", 1, 0, 0, [CardDataScript.CardTag.WEAPON]
	)
	var result := CombatServiceScript.new().resolve_encounter(
		_make_stats(10, 10, 0, 0),
		[root, first_weapon, second_weapon],
		_make_mob("Wolf", 10, 0, [_make_action(MobActionScript.Type.ATTACK, 1)])
	)

	_expect(result.steps.size() == 4, "root plus two combo weapons receive one shared response")
	_expect(result.player_stats_after.hp == 9, "adjacent weapon combo takes one monster action")
	_expect(_count_monster_steps(result) == 1, "adjacent weapons produce exactly one monster step")


func _test_service_non_adjacent_weapons_receive_one_action_per_card() -> void:
	var root := _make_combo_root()
	var first_weapon := _make_card(
		CardDataScript.CardType.NORMAL, "First Weapon", 0, 0, 0, [CardDataScript.CardTag.WEAPON]
	)
	var interrupt := _make_card(CardDataScript.CardType.NORMAL, "Interrupt")
	var second_weapon := _make_card(
		CardDataScript.CardType.NORMAL, "Second Weapon", 0, 0, 0, [CardDataScript.CardTag.WEAPON]
	)
	var result := CombatServiceScript.new().resolve_encounter(
		_make_stats(10, 10, 0, 0),
		[root, first_weapon, interrupt, second_weapon],
		_make_mob("Wolf", 10, 0, [_make_action(MobActionScript.Type.ATTACK, 1)])
	)

	_expect(_count_monster_steps(result) == 3, "non-adjacent weapons receive one action per card")
	_expect(result.player_stats_after.hp == 7, "three distinct batches apply three monster attacks")


func _test_service_low_hp_rule_uses_pre_card_context() -> void:
	var low_hp_condition := PlayerHpRatioConditionScript.new()
	low_hp_condition.threshold = 0.5
	low_hp_condition.comparison = CardConditionScript.Comparison.LESS_THAN
	var extra_heal := AddHealOperationScript.new()
	extra_heal.amount = 3
	var rule := CardRuleScript.new()
	rule.condition = low_hp_condition
	rule.operation = extra_heal
	var recovery := _make_card(CardDataScript.CardType.NORMAL, "Recovery", 0, 0, 1)
	recovery.card_data.effect_rules = [rule]
	var result := CombatServiceScript.new().resolve_encounter(
		_make_stats(10, 4, 0, 0),
		[_make_card(CardDataScript.CardType.ROOT, "Root"), recovery],
		_make_mob("Wolf", 10, 0, [_make_action(MobActionScript.Type.DEFEND, 0)])
	)

	_expect(result.player_stats_after.hp == 8, "low-HP rule emits extra heal from pre-card HP")
	if result.steps.size() >= 2:
		_expect(result.steps[1].effects.size() == 1, "recovery combines base and conditional healing")
		if result.steps[1].effects.size() == 1:
			_expect(result.steps[1].effects[0].value == 4, "conditional heal uses pre-card HP")


func _test_service_retreat_adds_tail_penalty() -> void:
	var result := CombatServiceScript.new().resolve_encounter(
		_make_stats(10, 10, 0, 0),
		[_make_card(CardDataScript.CardType.ROOT, "Root"), _make_card(CardDataScript.CardType.NORMAL, "Wait")],
		_make_mob("Wolf", 10, 0, [_make_action(MobActionScript.Type.DEFEND, 1)])
	)

	_expect(result.outcome == CombatResultScript.Outcome.RETREAT, "exhausted living actors retreat")
	_expect(result.penalties.size() == 1, "retreat creates one penalty")
	if result.penalties.size() == 1:
		_expect(result.penalties[0].type == CombatPenaltyScript.Type.REMOVE_CARD, "retreat removes a card")
		_expect(result.penalties[0].amount == 1, "retreat removes one card")
		_expect(
			result.penalties[0].target == CombatPenaltyScript.Target.TAIL_OF_CARD_CHAIN,
			"retreat penalty targets the chain tail"
		)


func _test_service_monster_attack_defeats_immediately() -> void:
	var result := CombatServiceScript.new().resolve_encounter(
		_make_stats(10, 2, 0, 0),
		[
			_make_card(CardDataScript.CardType.ROOT, "Root"),
			_make_card(CardDataScript.CardType.NORMAL, "First"),
			_make_card(CardDataScript.CardType.NORMAL, "Never Resolved"),
		],
		_make_mob("Wolf", 10, 0, [_make_action(MobActionScript.Type.ATTACK, 2)])
	)

	_expect(result.outcome == CombatResultScript.Outcome.DEFEAT, "zero player HP causes immediate defeat")
	_expect(result.processed_card_count == 2, "defeat stops before later cards")
	_expect(result.steps.size() == 3, "defeat records only root, player card, and lethal action")
	_expect(result.penalties.is_empty(), "defeat does not create a retreat penalty")


func _test_service_steps_are_ordered_and_isolated() -> void:
	var result := CombatServiceScript.new().resolve_encounter(
		_make_stats(10, 10, 0, 0),
		[_make_card(CardDataScript.CardType.ROOT, "Root"), _make_card(CardDataScript.CardType.NORMAL, "Strike", 3)],
		_make_mob("Wolf", 10, 0, [_make_action(MobActionScript.Type.ATTACK, 2)])
	)

	_expect(result.steps.size() == 3, "service returns the ordered combat log")
	if result.steps.size() != 3:
		return
	_expect(result.steps[0].kind == CombatStepScript.Kind.ROOT_CARD, "first step is root")
	_expect(result.steps[1].kind == CombatStepScript.Kind.PLAYER_CARD, "second step is player card")
	_expect(result.steps[2].kind == CombatStepScript.Kind.MONSTER_ACTION, "third step is monster action")
	_expect(
		result.steps[1].monster_before.hp == 10 and result.steps[1].monster_after.hp == 7,
		"player step owns before and after monster snapshots"
	)
	_expect(
		result.steps[2].player_before.hp == 10 and result.steps[2].player_after.hp == 8,
		"monster step owns before and after player snapshots"
	)
	result.steps[0].player_after.hp = 0
	_expect(result.steps[1].player_before.hp == 10, "step snapshots do not share mutable stats")


func _test_service_input_monster_remains_unchanged() -> void:
	var player := _make_stats(10, 9, 0, 0)
	var monster := _make_mob("Wolf", 10, 2, [_make_action(MobActionScript.Type.ATTACK, 1)])
	monster.action_index = 0
	var result := CombatServiceScript.new().resolve_encounter(
		player,
		[_make_card(CardDataScript.CardType.ROOT, "Root"), _make_card(CardDataScript.CardType.NORMAL, "Strike", 3)],
		monster
	)

	_expect(player.hp == 9 and player.defense == 0, "service does not mutate input player stats")
	_expect(monster.action_index == 0, "service does not mutate input monster action index")
	_expect(monster.stats.hp == 10 and monster.stats.defense == 2, "service does not mutate input monster stats")
	_expect(result.monster_stats_after.hp == 9, "result owns the encounter-local monster stats")


func _test_service_root_to_weapon_flushes_before_retreat() -> void:
	var weapon := _make_card(
		CardDataScript.CardType.NORMAL, "Lone Weapon", 0, 0, 0, [CardDataScript.CardTag.WEAPON]
	)
	var result := CombatServiceScript.new().resolve_encounter(
		_make_stats(10, 10, 0, 0),
		[_make_combo_root(), weapon],
		_make_mob("Wolf", 10, 0, [_make_action(MobActionScript.Type.ATTACK, 1)])
	)

	_expect(result.outcome == CombatResultScript.Outcome.RETREAT, "living player retreats after flush")
	_expect(result.steps.size() == 3, "root-to-weapon flush resolves an action before retreat")
	_expect(_count_monster_steps(result) == 1, "flush produces exactly one monster action")
	_expect(result.player_stats_after.hp == 9, "flush action affects the surviving player")


func _test_service_null_monster_action_records_empty_step() -> void:
	var result := CombatServiceScript.new().resolve_encounter(
		_make_stats(10, 10, 0, 0),
		[_make_card(CardDataScript.CardType.ROOT, "Root"), _make_card(CardDataScript.CardType.NORMAL, "Wait")],
		_make_mob("Silent Wolf", 10, 0, [])
	)

	_expect(result.steps.size() == 3, "null monster action still creates a combat step")
	if result.steps.size() == 3:
		_expect(result.steps[2].kind == CombatStepScript.Kind.MONSTER_ACTION, "null action is a monster step")
		_expect(result.steps[2].effects.is_empty(), "null monster action has no effects")


func _make_combo_root() -> CardInstance:
	var root := _make_card(CardDataScript.CardType.ROOT, "Combo Root")
	root.card_data.root_rule_providers = [WeaponComboRootRuleProviderScript.new()]
	return root


func _make_card(
	card_type: CardData.CardType,
	card_name: String,
	damage := 0,
	defense := 0,
	heal := 0,
	tags: Array[CardData.CardTag] = []
) -> CardInstance:
	var data := CardDataScript.new()
	data.card_type = card_type
	data.card_name = card_name
	data.damage = damage
	data.defense = defense
	data.heal = heal
	data.tags = tags.duplicate()
	return CardInstanceScript.new(data)


func _make_action(type: MobAction.Type, value: int) -> MobAction:
	var action := MobActionScript.new()
	action.type = type
	action.value = value
	return action


func _make_mob(
	mob_name: String, hp: int, defense: int, actions: Array[MobAction]
) -> MobInstance:
	var stats_data := CombatStatsDataScript.new()
	stats_data.max_hp = hp
	stats_data.attack = 0
	stats_data.defense = defense
	var data := MobDataScript.new()
	data.mob_name = mob_name
	data.base_stats = stats_data
	data.actions = actions
	var monster := data.create_instance()
	monster.stats.hp = hp
	monster.stats.defense = defense
	return monster


func _count_monster_steps(result: CombatResult) -> int:
	var count := 0
	for step in result.steps:
		if step != null and step.kind == CombatStepScript.Kind.MONSTER_ACTION:
			count += 1
	return count


func _make_card_with_tag(tag: CardData.CardTag) -> CardInstance:
	var data := CardDataScript.new()
	data.tags = [tag]
	return CardInstanceScript.new(data)


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
