extends SceneTree

const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const CombatContextScript = preload("res://scripts/combatv2/combat_context.gd")
const CombatEffectDraftScript = preload("res://scripts/combatv2/combat_effect_draft.gd")
const CombatEffectScript = preload("res://scripts/combatv2/card/combat_effect.gd")
const PreviousWeaponDamageDoubleRuleScript = preload(
	"res://scripts/combatv2/card/rules/previous_weapon_damage_double_rule.gd"
)
const FirstCardDamageDoubleRuleScript = preload(
	"res://scripts/combatv2/card/rules/first_card_damage_double_rule.gd"
)
const LastCardDefenseDoubleRuleScript = preload(
	"res://scripts/combatv2/card/rules/last_card_defense_double_rule.gd"
)

var _failure_count := 0


func _init() -> void:
	_test_previous_weapon_doubles_current_card_damage()
	_test_first_card_doubles_damage()
	_test_last_card_doubles_defense()
	call_deferred("_finish_tests")


func _test_previous_weapon_doubles_current_card_damage() -> void:
	var previous := _make_card("Previous Weapon", 0, 0, [CardData.CardTag.WEAPON])
	var current := _make_card("Current Attack", 5)
	var state := CombatContextScript.new(null, null, [previous, current])
	state.resolved_cards.append(previous)
	state.remaining_cards.erase(previous)
	var draft = _make_attack_draft(state, current, 5)

	_expect(PreviousWeaponDamageDoubleRuleScript.new().on_attack(draft), "weapon rule reports a changed effect draft")
	_expect(draft.get_monster_damage_effect().value == 10, "previous WEAPON card doubles current effect damage")


func _test_first_card_doubles_damage() -> void:
	var first := _make_card("First Attack", 4)
	var state := CombatContextScript.new(null, null, [first])
	var draft = _make_attack_draft(state, first, 4)

	_expect(FirstCardDamageDoubleRuleScript.new().on_attack(draft), "first-card rule reports a changed effect draft")
	_expect(draft.get_monster_damage_effect().value == 8, "first card doubles outgoing effect damage")


func _test_last_card_doubles_defense() -> void:
	var first := _make_card("First", 0, 1)
	var last := _make_card("Last Defense", 0, 3)
	var state := CombatContextScript.new(null, null, [first, last])
	state.resolved_cards.append(first)
	state.remaining_cards.erase(first)
	var draft = _make_attack_draft(state, last, 1)

	_expect(LastCardDefenseDoubleRuleScript.new().on_attack(draft), "last-card defense rule reports a changed effect draft")
	var defense_effects = draft.find_effects(CombatEffectScript.Type.ADD_DEFENSE, CombatEffectScript.Target.PLAYER)
	_expect(defense_effects.size() == 1 and defense_effects[0].value == 6, "last card doubles its defense effect")


func _make_attack_draft(state: CombatContext, current: CardInstance, damage: int):
	var draft := CombatEffectDraftScript.new(state, current)
	draft.add_damage(
		CombatEffectScript.Target.MONSTER,
		damage,
		CombatEffectScript.SourceType.PLAYER_CARD,
		current.card_data.card_name
	)
	return draft


func _make_card(
	card_name: String, damage: int, defense: int = 0, tags: Array[CardData.CardTag] = []
) -> CardInstance:
	var data := CardDataScript.new()
	data.card_name = card_name
	data.damage = damage
	data.defense = defense
	data.tags = tags
	return CardInstanceScript.new(data)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)


func _finish_tests() -> void:
	quit(0 if _failure_count == 0 else 1)
