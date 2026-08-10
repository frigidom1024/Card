extends SceneTree

const Root = preload("res://data/levels/ribwood/cards/ribwood_guardian_root.tres")
const Blade = preload("res://data/levels/ribwood/cards/ribwood_rib_blade.tres")
const Tinder = preload("res://data/levels/ribwood/cards/ribwood_old_tinder.tres")
const Shield = preload("res://data/levels/ribwood/cards/ribwood_folded_rib_shield.tres")
const Flask = preload("res://data/levels/ribwood/cards/ribwood_warm_marrow_flask.tres")
const RibNail = preload("res://data/levels/ribwood/cards/ribwood_rib_nail.tres")
const ShieldFragment = preload("res://data/levels/ribwood/cards/ribwood_shield_fragment.tres")
const AmberMarrowBottle = preload("res://data/levels/ribwood/cards/ribwood_amber_marrow_bottle.tres")
const BoneArmorRoundShield = preload("res://data/levels/ribwood/cards/ribwood_bone_armor_round_shield.tres")
const EmberBlade = preload("res://data/levels/ribwood/cards/ribwood_ember_blade.tres")
const WarmthCharm = preload("res://data/levels/ribwood/cards/ribwood_warmth_charm.tres")
const ScarBottle = preload("res://data/levels/ribwood/cards/ribwood_scar_bottle.tres")
const GraveBeetle = preload("res://data/levels/ribwood/cards/ribwood_grave_beetle.tres")
const BoneStitchNeedle = preload("res://data/levels/ribwood/cards/ribwood_bone_stitch_needle.tres")
const BrokenBannerScout = preload("res://data/levels/ribwood/cards/ribwood_broken_banner_scout.tres")
const OldChestCloak = preload("res://data/levels/ribwood/cards/ribwood_old_chest_cloak.tres")
const LastStandStrike = preload("res://data/levels/ribwood/cards/ribwood_last_stand_strike.tres")
const WhiteHornRelic = preload("res://data/levels/ribwood/cards/ribwood_white_horn_relic.tres")
const SternumPlate = preload("res://data/levels/ribwood/cards/ribwood_sternum_plate.tres")
const GuardianEmber = preload("res://data/levels/ribwood/cards/ribwood_guardian_ember.tres")
const StartingDeck = preload("res://data/starting_decks/revival_starting_deck.tres")
const NextCardArmorBonusRule = preload(
	"res://scripts/combatv2/card/rules/next_card_armor_bonus_rule.gd"
)
const ArmoredNextCardPointBonusRule = preload(
	"res://scripts/combatv2/card/rules/armored_next_card_point_bonus_rule.gd"
)
const ChainLengthHeadPointBonusRule = preload(
	"res://scripts/combatv2/card/rules/chain_length_head_point_bonus_rule.gd"
)
const ChainLengthHeadArmorBonusRule = preload(
	"res://scripts/combatv2/card/rules/chain_length_head_armor_bonus_rule.gd"
)
const BehindHeadPreTriggerRule = preload(
	"res://scripts/combatv2/card/rules/behind_head_pre_trigger_rule.gd"
)
const CombatStartPointBonusRule = preload(
	"res://scripts/combatv2/card/rules/combat_start_point_bonus_rule.gd"
)

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_starter_card_point_contract()
	_test_full_ribwood_card_pool_contract()
	_test_starter_deck_uses_ribwood_cards_and_guide()
	quit(1 if _failure_count > 0 else 0)


func _test_starter_card_point_contract() -> void:
	_expect(Root.card_type == CardData.CardType.ROOT, "guardian root is ROOT")
	_expect(Root.max_points == 2 and Root.armor == 0, "guardian root starts at 2 points")
	_expect(
		Blade.max_points == 2 and Blade.tags.has(CardData.CardTag.WEAPON),
		"rib blade is a 2-point weapon"
	)
	var expected_rule_script := load("res://scripts/combatv2/card/rules/combat_start_point_bonus_rule.gd") as Script
	_expect(expected_rule_script != null, "combat-start point bonus rule exists")
	_expect(Blade.effect_rules.size() == 1, "rib blade has one combat-start rule")
	if expected_rule_script != null and Blade.effect_rules.size() == 1:
		_expect(
			Blade.effect_rules[0].get_script() == expected_rule_script
			and Blade.effect_rules[0].get("bonus_points") == 2,
			"rib blade gains two temporary points at combat start"
		)
	_expect(Tinder.max_points == 1 and Tinder.armor == 0, "old tinder starts at one point")
	_expect(Shield.max_points == 1 and Shield.armor == 1, "folded shield supplies a point and armor")
	_expect(Shield.effect_rules.size() == 1, "folded shield has one placement rule")
	if Shield.effect_rules.size() == 1:
		_expect(
			Shield.effect_rules[0].get_script() == NextCardArmorBonusRule
			and Shield.effect_rules[0].get("armor") == 1,
			"folded shield grants the next card one armor"
		)
	_expect(Flask.max_points == 1 and Flask.armor == 1, "warm flask is a low-point armor card")


func _test_full_ribwood_card_pool_contract() -> void:
	_expect_card(Root, 2, 0, 1, CardData.Rarity.COMMON, "牌链唯一合法的开端。点数耗尽时，重整后返回手牌。")
	_expect_card(Blade, 2, 0, 2, CardData.Rarity.COMMON, "从灰白肋骨上削下的短刃。战斗开始时，本牌获得 +2 点数；战斗结束后移除该加成。")
	_expect_card(Tinder, 1, 0, 2, CardData.Rarity.COMMON, "从旧营火留下的干燥火绒。无额外效果。")
	_expect_card(Shield, 1, 1, 2, CardData.Rarity.COMMON, "可以折起挂在行囊侧面的肋骨圆盾。每当你在本牌前方放置一张卡牌时，该卡牌获得 +1 护甲。")
	_expect_card(Flask, 1, 1, 2, CardData.Rarity.COMMON, "保温的骨髓水囊。无额外效果。")
	_expect_card(RibNail, 3, 0, 2, CardData.Rarity.COMMON, "从肋骨边缘拔下的长钉，沉重却可靠。无额外效果。")
	_expect_card(ShieldFragment, 1, 1, 2, CardData.Rarity.COMMON, "裂开的肋盾碎片。本牌前方的下一张卡牌获得 +2 护甲。此效果仅生效 1 次。")
	_expect_card(AmberMarrowBottle, 2, 2, 2, CardData.Rarity.COMMON, "封着暖金色骨髓的玻璃瓶。无额外效果。")
	_expect_card(BoneArmorRoundShield, 1, 2, 2, CardData.Rarity.COMMON, "用旧骨甲削成的圆盾。本牌前方的下一张卡牌获得 +2 护甲。此效果仅生效 2 次。")
	_expect_card(EmberBlade, 3, 0, 4, CardData.Rarity.RARE, "仍带余温的短刃。只要本牌仍在牌链中，当你放置的卡牌使牌链达到 4 张或以上时，该头部卡牌获得 +2 点数。此效果仅生效 1 次。")
	_expect_card(WarmthCharm, 2, 1, 4, CardData.Rarity.RARE, "缠在腕上的余温护符。只要本牌仍在牌链中，当你放置的卡牌使牌链达到 4 张或以上时，该头部卡牌获得 +2 护甲。此效果仅生效 1 次。")
	_expect_card(ScarBottle, 2, 2, 2, CardData.Rarity.COMMON, "装着结痂粉末的小瓶。无额外效果。")
	_expect_card(GraveBeetle, 3, 2, 4, CardData.Rarity.RARE, "守墓甲虫伏在行囊上，硬壳会替旅人承受撞击。无额外效果。")
	_expect_card(BoneStitchNeedle, 2, 0, 4, CardData.Rarity.RARE, "缝补披风和行囊的骨针。当你在本牌前方放置一张具有护甲的卡牌时，该卡牌获得 +2 点数。此效果仅生效 2 次。")
	_expect_card(OldChestCloak, 2, 2, 2, CardData.Rarity.COMMON, "胸前磨白的旧斗篷，缝线里夹着干燥草药。无额外效果。")
	_expect_card(LastStandStrike, 4, 0, 4, CardData.Rarity.RARE, "走投无路时挥出的重击。无额外效果。")
	_expect_card(WhiteHornRelic, 3, 1, 8, CardData.Rarity.EPIC, "白角守墓鹿遗下的一截角片，既锋利又能挡住一次冲撞。无额外效果。")
	_expect_card(SternumPlate, 2, 2, 8, CardData.Rarity.EPIC, "厚重的胸骨护板。本牌前方的下一张卡牌获得 +2 护甲。此效果仅生效 1 次。")
	_expect_card(GuardianEmber, 2, 3, 8, CardData.Rarity.EPIC, "守护余烬藏在灯罩里，光不强，却足以护住下一步。无额外效果。")
	_expect_card(BrokenBannerScout, 2, 1, 2, CardData.Rarity.COMMON, "绑在行囊侧面的断旗，总比行者先迎上风。当本牌紧邻牌链头部时，战斗开始前先攻击一次，只造成伤害，不会受到残响反击。")

	_expect_rule(Blade, CombatStartPointBonusRule, {"bonus_points": 2, "effective_count": -1})
	_expect_rule(Shield, NextCardArmorBonusRule, {"armor": 1, "effective_count": -1})
	_expect_rule(ShieldFragment, NextCardArmorBonusRule, {"armor": 2, "effective_count": 1})
	_expect_rule(BoneArmorRoundShield, NextCardArmorBonusRule, {"armor": 2, "effective_count": 2})
	_expect_rule(EmberBlade, ChainLengthHeadPointBonusRule, {"minimum_chain_size": 4, "bonus_points": 2, "effective_count": 1})
	_expect_rule(WarmthCharm, ChainLengthHeadArmorBonusRule, {"minimum_chain_size": 4, "armor": 2, "effective_count": 1})
	_expect_rule(BoneStitchNeedle, ArmoredNextCardPointBonusRule, {"bonus_points": 2, "effective_count": 2})
	_expect_rule(SternumPlate, NextCardArmorBonusRule, {"armor": 2, "effective_count": 1})
	_expect_rule(BrokenBannerScout, BehindHeadPreTriggerRule, {"effective_count": -1})

	for card in [Root, Tinder, Flask, RibNail, AmberMarrowBottle, ScarBottle, GraveBeetle, OldChestCloak, LastStandStrike, WhiteHornRelic, GuardianEmber]:
		_expect(card.effect_rules.is_empty(), "%s has no placement rule" % card.card_name)


func _expect_card(
	card: CardData, expected_points: int, expected_armor: int, expected_value: int,
	expected_rarity: CardData.Rarity, expected_description: String
) -> void:
	_expect(card.max_points == expected_points, "%s has expected points" % card.card_name)
	_expect(card.armor == expected_armor, "%s has expected armor" % card.card_name)
	_expect(card.value == expected_value, "%s has expected value" % card.card_name)
	_expect(card.rarity == expected_rarity, "%s has expected rarity" % card.card_name)
	_expect(card.description == expected_description, "%s has complete player-facing description" % card.card_name)


func _expect_rule(card: CardData, expected_script: Script, expected_values: Dictionary) -> void:
	_expect(card.effect_rules.size() == 1, "%s has one placement rule" % card.card_name)
	if card.effect_rules.size() != 1:
		return
	var rule := card.effect_rules[0]
	_expect(rule.get_script() == expected_script, "%s uses the expected rule class" % card.card_name)
	for property_name in expected_values:
		_expect(
			rule.get(property_name) == expected_values[property_name],
			"%s configures %s correctly" % [card.card_name, property_name]
		)


func _test_starter_deck_uses_ribwood_cards_and_guide() -> void:
	_expect(StartingDeck.validate().is_empty(), "Ribwood starting deck validates")
	_expect(StartingDeck.starter_cards.size() == 6, "Ribwood starting deck has five cards and one guide")
	var guide_count := 0
	var ribwood_card_count := 0
	for card in StartingDeck.starter_cards:
		if card.card_type == CardData.CardType.GUIDE:
			guide_count += 1
		elif card.resource_path.begins_with("res://data/levels/ribwood/cards/"):
			ribwood_card_count += 1
	_expect(guide_count == 1, "starting deck includes one guide card")
	_expect(ribwood_card_count == 5, "five playable starter cards are scoped to Ribwood")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)