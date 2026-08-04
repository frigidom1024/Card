extends SceneTree

const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const CombatContextScript = preload("res://scripts/combatv2/combat_context.gd")
const CombatStatsScript = preload("res://scripts/combatv2/combat_stats.gd")
const CardResolutionContextScript = preload("res://scripts/combatv2/card/card_resolution_context.gd")
const CardResolutionDraftScript = preload("res://scripts/combatv2/card/card_resolution_draft.gd")
const PreviousWeaponRule = preload("res://scripts/combatv2/card/rules/previous_weapon_damage_bonus_rule.gd")
const PreviousDefenseDamageRule = preload("res://scripts/combatv2/card/rules/previous_defense_damage_bonus_rule.gd")
const PreviousDefenseHealRule = preload("res://scripts/combatv2/card/rules/previous_defense_heal_bonus_rule.gd")
const LastDefenseRule = preload("res://scripts/combatv2/card/rules/last_card_defense_bonus_rule.gd")
const Root = preload("res://data/levels/ribwood/cards/ribwood_guardian_root.tres")
const Blade = preload("res://data/levels/ribwood/cards/ribwood_rib_blade.tres")
const Tinder = preload("res://data/levels/ribwood/cards/ribwood_old_tinder.tres")
const Shield = preload("res://data/levels/ribwood/cards/ribwood_folded_rib_shield.tres")
const Flask = preload("res://data/levels/ribwood/cards/ribwood_warm_marrow_flask.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_weapon_follow_up()
	_test_defense_follow_up_damage()
	_test_defense_follow_up_heal()
	_test_tail_defense()
	_test_empty_context_is_safe()
	quit(1 if _failure_count > 0 else 0)


func _test_weapon_follow_up() -> void:
	var previous := CardInstanceScript.new(Blade)
	var current := CardInstanceScript.new(Tinder)
	var context := _context([previous, current], previous, current, 1)
	var draft := CardResolutionDraftScript.from_card(current.card_data)
	PreviousWeaponRule.new().execute(context, draft)
	_expect(draft.damage == 2, "old tinder gains +1 damage after a weapon")


func _test_defense_follow_up_damage() -> void:
	var previous := CardInstanceScript.new(Shield)
	var current := CardInstanceScript.new(Tinder)
	var context := _context([previous, current], previous, current, 1)
	var draft := CardResolutionDraftScript.from_card(current.card_data)
	PreviousDefenseDamageRule.new().execute(context, draft)
	_expect(draft.damage == 3, "defense follow-up damage gains +2")


func _test_defense_follow_up_heal() -> void:
	var previous := CardInstanceScript.new(Shield)
	var current := CardInstanceScript.new(Flask)
	var context := _context([previous, current], previous, current, 1)
	var draft := CardResolutionDraftScript.from_card(current.card_data)
	PreviousDefenseHealRule.new().execute(context, draft)
	_expect(draft.heal == 3, "defense follow-up healing gains +1")


func _test_tail_defense() -> void:
	var previous := CardInstanceScript.new(Root)
	var current := CardInstanceScript.new(Shield)
	var context := _context([previous, current], previous, current, 1)
	var draft := CardResolutionDraftScript.from_card(current.card_data)
	LastDefenseRule.new().execute(context, draft)
	_expect(draft.defense == 4, "tail folded shield gains +2 defense")


func _test_empty_context_is_safe() -> void:
	var draft := CardResolutionDraftScript.from_card(Tinder)
	PreviousWeaponRule.new().execute(null, draft)
	LastDefenseRule.new().execute(null, draft)
	_expect(draft.damage == 1, "rules preserve values for empty context")


func _context(cards: Array, previous: CardInstance, current: CardInstance, index: int) -> CardResolutionContext:
	var player := CombatStatsScript.new()
	player.max_hp = 20
	player.hp = 20
	var typed_cards: Array[CardInstance] = []
	for card in cards:
		if card != null:
			typed_cards.append(card as CardInstance)
	var state := CombatContextScript.new(player, null, typed_cards)
	state.resolved_cards.append(previous)
	state.remaining_cards.erase(previous)
	return CardResolutionContextScript.new(state, current, index)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
