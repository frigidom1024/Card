extends SceneTree

const CardChainRuleServiceScript = preload("res://scripts/card/card_chain_rule_service.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const Root = preload("res://data/levels/ribwood/cards/ribwood_guardian_root.tres")
const Blade = preload("res://data/levels/ribwood/cards/ribwood_rib_blade.tres")
const Tinder = preload("res://data/levels/ribwood/cards/ribwood_old_tinder.tres")
const Shield = preload("res://data/levels/ribwood/cards/ribwood_folded_rib_shield.tres")
const Flask = preload("res://data/levels/ribwood/cards/ribwood_warm_marrow_flask.tres")
const BoneStitchNeedle = preload("res://data/levels/ribwood/cards/ribwood_bone_stitch_needle.tres")
const EmberBlade = preload("res://data/levels/ribwood/cards/ribwood_ember_blade.tres")
const WarmthCharm = preload("res://data/levels/ribwood/cards/ribwood_warmth_charm.tres")
const ShieldFragment = preload("res://data/levels/ribwood/cards/ribwood_shield_fragment.tres")
const BoneArmorRoundShield = preload("res://data/levels/ribwood/cards/ribwood_bone_armor_round_shield.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_rib_blade_does_not_trigger_on_card_placement()
	_test_folded_rib_shield_protects_its_next_card()
	_test_bone_stitch_needle_requires_an_armored_next_card()
	_test_ember_blade_rewards_only_the_qualifying_long_chain_head()
	_test_warmth_charm_grants_limited_long_chain_head_armor()
	_test_finite_ribwood_support_cards_exhaust_after_configured_uses()
	quit(1 if _failure_count > 0 else 0)


func _test_rib_blade_does_not_trigger_on_card_placement() -> void:
	var root := CardInstanceScript.new(Root)
	var blade := CardInstanceScript.new(Blade)
	var tinder := CardInstanceScript.new(Tinder)
	var chain: Array[CardInstance] = [root, blade, tinder]

	var applied := CardChainRuleServiceScript.new().resolve_card_added(chain, tinder)

	_expect(applied == 0, "Rib Blade no longer triggers during card placement")
	_expect(tinder.current_points == 1, "placing a card does not change its points")
	_expect(blade.get_rule_trigger_count(0) == 0, "Rib Blade keeps its combat-start rule unused")


func _test_folded_rib_shield_protects_its_next_card() -> void:
	var root := CardInstanceScript.new(Root)
	var shield := CardInstanceScript.new(Shield)
	var flask := CardInstanceScript.new(Flask)
	var chain: Array[CardInstance] = [root, shield, flask]

	var applied := CardChainRuleServiceScript.new().resolve_card_added(chain, flask)

	_expect(applied == 1, "placing Warm Marrow Flask triggers Folded Rib Shield once")
	_expect(flask.current_armor == 2, "Folded Rib Shield grants its next card one armor")
	_expect(shield.get_rule_trigger_count(0) == 1, "Folded Rib Shield records its successful use")


func _test_bone_stitch_needle_requires_an_armored_next_card() -> void:
	var root := CardInstanceScript.new(Root)
	var needle := CardInstanceScript.new(BoneStitchNeedle)
	var unarmored_tinder := CardInstanceScript.new(Tinder)
	var unarmored_chain: Array[CardInstance] = [root, needle, unarmored_tinder]
	var service := CardChainRuleServiceScript.new()

	service.resolve_card_added(unarmored_chain, unarmored_tinder)

	_expect(unarmored_tinder.current_points == 1, "needle does not empower an unarmored next card")
	_expect(needle.get_rule_trigger_count(0) == 0, "failed needle condition consumes no use")

	var armored_flask := CardInstanceScript.new(Flask)
	var armored_chain: Array[CardInstance] = [root, needle, armored_flask]
	service.resolve_card_added(armored_chain, armored_flask)

	_expect(armored_flask.current_points == 3, "needle grants two points to an armored next card")
	_expect(needle.get_rule_trigger_count(0) == 1, "needle records its successful use")


func _test_ember_blade_rewards_only_the_qualifying_long_chain_head() -> void:
	var root := CardInstanceScript.new(Root)
	var ember_blade := CardInstanceScript.new(EmberBlade)
	var first_head := CardInstanceScript.new(Tinder)
	var second_head := CardInstanceScript.new(Tinder)
	var service := CardChainRuleServiceScript.new()

	service.resolve_card_added(
		[root, ember_blade, CardInstanceScript.new(Flask), first_head], first_head
	)
	service.resolve_card_added(
		[root, ember_blade, CardInstanceScript.new(Flask), second_head], second_head
	)

	_expect(first_head.current_points == 3, "ember blade gives the four-card head two points")
	_expect(second_head.current_points == 1, "ember blade does not empower a second head after its use")
	_expect(ember_blade.get_rule_trigger_count(0) == 1, "ember blade has one successful trigger")


func _test_warmth_charm_grants_limited_long_chain_head_armor() -> void:
	var root := CardInstanceScript.new(Root)
	var charm := CardInstanceScript.new(WarmthCharm)
	var first_head := CardInstanceScript.new(Tinder)
	var second_head := CardInstanceScript.new(Tinder)
	var service := CardChainRuleServiceScript.new()

	service.resolve_card_added([root, charm, CardInstanceScript.new(Flask), first_head], first_head)
	service.resolve_card_added([root, charm, CardInstanceScript.new(Flask), second_head], second_head)

	_expect(first_head.current_armor == 2, "warmth charm grants two armor to the qualifying head")
	_expect(second_head.current_armor == 0, "warmth charm grants no armor after its use")
	_expect(charm.get_rule_trigger_count(0) == 1, "warmth charm has one successful trigger")


func _test_finite_ribwood_support_cards_exhaust_after_configured_uses() -> void:
	var root := CardInstanceScript.new(Root)
	var fragment := CardInstanceScript.new(ShieldFragment)
	var fragment_first := CardInstanceScript.new(Tinder)
	var fragment_second := CardInstanceScript.new(Tinder)
	var round_shield := CardInstanceScript.new(BoneArmorRoundShield)
	var shield_first := CardInstanceScript.new(Tinder)
	var shield_second := CardInstanceScript.new(Tinder)
	var shield_third := CardInstanceScript.new(Tinder)
	var service := CardChainRuleServiceScript.new()

	service.resolve_card_added([root, fragment, fragment_first], fragment_first)
	service.resolve_card_added([root, fragment, fragment_second], fragment_second)
	service.resolve_card_added([root, round_shield, shield_first], shield_first)
	service.resolve_card_added([root, round_shield, shield_second], shield_second)
	service.resolve_card_added([root, round_shield, shield_third], shield_third)

	_expect(fragment_first.current_armor == 2, "shield fragment protects its first next card")
	_expect(fragment_second.current_armor == 0, "shield fragment is exhausted after one use")
	_expect(shield_first.current_armor == 2, "round shield protects its first next card")
	_expect(shield_second.current_armor == 2, "round shield protects its second next card")
	_expect(shield_third.current_armor == 0, "round shield is exhausted after two uses")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
