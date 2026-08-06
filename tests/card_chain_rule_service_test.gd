extends SceneTree

const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const CardChainRuleServiceScript = preload("res://scripts/card/card_chain_rule_service.gd")
const NextCardPointBonusRuleScript = preload(
	"res://scripts/combatv2/card/rules/next_card_point_bonus_rule.gd"
)
const NextCardArmorBonusRuleScript = preload(
	"res://scripts/combatv2/card/rules/next_card_armor_bonus_rule.gd"
)

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_adjacent_support_grants_points_to_added_card()
	_test_infinite_rule_supports_each_new_adjacent_card()
	_test_effective_count_stops_after_successful_uses()
	_test_non_adjacent_card_does_not_consume_rule_use()
	_test_adjacent_support_grants_armor()
	quit(1 if _failure_count > 0 else 0)


func _test_adjacent_support_grants_points_to_added_card() -> void:
	var support := _card("垫脚石", 1)
	var rule := NextCardPointBonusRuleScript.new()
	rule.bonus_points = 1
	support.card_data.effect_rules.append(rule)
	var added := _card("短刃", 2)

	var applied := CardChainRuleServiceScript.new().resolve_card_added([_root(), support, added], added)

	_expect(applied == 1, "adjacent point rule reports one application")
	_expect(added.current_points == 3, "adjacent point rule grants the added card one point")


func _test_infinite_rule_supports_each_new_adjacent_card() -> void:
	var support := _card("前探火把", 1)
	var rule := NextCardPointBonusRuleScript.new()
	rule.bonus_points = 2
	rule.effective_count = -1
	support.card_data.effect_rules.append(rule)
	var first_head := _card("第一张头部", 1)
	var second_head := _card("第二张头部", 1)
	var service := CardChainRuleServiceScript.new()

	service.resolve_card_added([_root(), support, first_head], first_head)
	service.resolve_card_added([_root(), support, second_head], second_head)

	_expect(first_head.current_points == 3, "infinite rule supports the first new head")
	_expect(second_head.current_points == 3, "infinite rule supports a replacement head")
	_expect(support.get_rule_trigger_count(0) == 2, "infinite rule records successful applications")


func _test_effective_count_stops_after_successful_uses() -> void:
	var support := _card("限次灯", 1)
	var rule := NextCardPointBonusRuleScript.new()
	rule.bonus_points = 1
	rule.effective_count = 2
	support.card_data.effect_rules.append(rule)
	var service := CardChainRuleServiceScript.new()
	var first := _card("第一张", 1)
	var second := _card("第二张", 1)
	var third := _card("第三张", 1)

	service.resolve_card_added([_root(), support, first], first)
	service.resolve_card_added([_root(), support, second], second)
	service.resolve_card_added([_root(), support, third], third)

	_expect(first.current_points == 2, "first successful use grants a point")
	_expect(second.current_points == 2, "second successful use grants a point")
	_expect(third.current_points == 1, "exhausted rule no longer grants points")
	_expect(support.get_rule_trigger_count(0) == 2, "finite rule stores only its successful uses")


func _test_non_adjacent_card_does_not_consume_rule_use() -> void:
	var support := _card("垫脚石", 1)
	var rule := NextCardPointBonusRuleScript.new()
	rule.bonus_points = 1
	rule.effective_count = 1
	support.card_data.effect_rules.append(rule)
	var spacer := _card("间隔卡", 1)
	var added := _card("头部", 1)

	var applied := CardChainRuleServiceScript.new().resolve_card_added(
		[_root(), support, spacer, added], added
	)

	_expect(applied == 0, "non-adjacent target does not apply the rule")
	_expect(added.current_points == 1, "non-adjacent target receives no points")
	_expect(support.get_rule_trigger_count(0) == 0, "failed position check does not consume a use")


func _test_adjacent_support_grants_armor() -> void:
	var support := _card("折叠圆盾", 1)
	var rule := NextCardArmorBonusRuleScript.new()
	rule.armor = 2
	rule.effective_count = 1
	support.card_data.effect_rules.append(rule)
	var added := _card("受护卡", 2)

	CardChainRuleServiceScript.new().resolve_card_added([_root(), support, added], added)

	_expect(added.current_armor == 2, "adjacent armor rule grants armor to the added card")
	_expect(support.get_rule_trigger_count(0) == 1, "successful armor rule consumes one use")


func _root() -> CardInstance:
	var data := CardDataScript.new()
	data.card_type = CardData.CardType.ROOT
	data.max_points = 2
	return CardInstanceScript.new(data)


func _card(name: String, max_points: int) -> CardInstance:
	var data := CardDataScript.new()
	data.card_name = name
	data.max_points = max_points
	return CardInstanceScript.new(data)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
