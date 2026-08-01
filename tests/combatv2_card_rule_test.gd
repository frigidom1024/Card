extends SceneTree

const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const CombatContextScript = preload("res://scripts/combatv2/combat_context.gd")
const CardResolutionContextScript = preload(
	"res://scripts/combatv2/card/card_resolution_context.gd"
)
const CardResolutionDraftScript = preload("res://scripts/combatv2/card/card_resolution_draft.gd")
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
	var context := CardResolutionContextScript.new(state, current, 1)
	var draft := CardResolutionDraftScript.from_card(current.card_data)

	PreviousWeaponDamageDoubleRuleScript.new().execute(context, draft)

	_expect(draft.damage == 10, "previous WEAPON card doubles current damage")


func _test_first_card_doubles_damage() -> void:
	var first := _make_card("First Attack", 4)
	var state := CombatContextScript.new(null, null, [first])
	var context := CardResolutionContextScript.new(state, first, 0)
	var draft := CardResolutionDraftScript.from_card(first.card_data)

	FirstCardDamageDoubleRuleScript.new().execute(context, draft)

	_expect(draft.damage == 8, "first card doubles its damage")


func _test_last_card_doubles_defense() -> void:
	var first := _make_card("First", 0, 1)
	var last := _make_card("Last Defense", 0, 3)
	var state := CombatContextScript.new(null, null, [first, last])
	state.resolved_cards.append(first)
	state.remaining_cards.erase(first)
	var context := CardResolutionContextScript.new(state, last, 1)
	var draft := CardResolutionDraftScript.from_card(last.card_data)

	LastCardDefenseDoubleRuleScript.new().execute(context, draft)

	_expect(draft.defense == 6, "last card doubles its defense")


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
