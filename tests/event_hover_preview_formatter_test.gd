extends SceneTree

const EventDataScript = preload("res://scripts/game/event/core/event_data.gd")
const EventInstanceScript = preload("res://scripts/game/event/core/event_instance.gd")
const EventHoverPreviewFormatterScript = preload(
	"res://scripts/game/event/hover/event_hover_preview_formatter.gd"
)
const EventHoverPreviewModelScript = preload(
	"res://scripts/game/event/hover/event_hover_preview_model.gd"
)
const MonsterEventContentScript = preload("res://scripts/game/event/encounter/monster_event_content.gd")
const BossEventContentScript = preload("res://scripts/game/event/encounter/boss_event_content.gd")
const MobDataScript = preload("res://scripts/game/event/encounter/mob_data.gd")
const MobActionScript = preload("res://scripts/game/event/encounter/mob_action.gd")
const EncounterDropEntryScript = preload("res://scripts/game/event/encounter/encounter_drop_entry.gd")
const EncounterRuntimeStateScript = preload("res://scripts/game/event/encounter/encounter_runtime_state.gd")
const CombatStatsScript = preload("res://scripts/combatv2/combat_stats.gd")
const CombatStatsDataScript = preload("res://scripts/combatv2/combat_stats_data.gd")
const CardDataScript = preload("res://scripts/card/card_data.gd")
const ShopEventContentScript = preload("res://scripts/game/event/shop/shop_event_content.gd")
const ShopItemDataScript = preload("res://scripts/game/event/shop/shop_item_data.gd")
const ShopRuntimeStateScript = preload("res://scripts/game/event/shop/shop_runtime_state.gd")
const TreasureEventContentScript = preload("res://scripts/game/event/treasure/treasure_event_content.gd")
const TreasureRuntimeStateScript = preload("res://scripts/game/event/treasure/treasure_runtime_state.gd")
const TreasureRewardOptionScript = preload("res://scripts/game/event/treasure/treasure_reward_option.gd")

var _failure_count := 0
var _formatter


func _init() -> void:
	_formatter = EventHoverPreviewFormatterScript.new()
	_test_monster_preview_uses_runtime_stats_and_formats_rewards_and_abilities()
	_test_boss_preview_uses_boss_label_and_defense()
	_test_shop_preview_filters_sold_items_and_formats_price()
	_test_treasure_preview_hides_unrolled_results_and_shows_cached_options()
	_test_resolved_event_is_not_visible()
	quit(1 if _failure_count > 0 else 0)


func _test_monster_preview_uses_runtime_stats_and_formats_rewards_and_abilities() -> void:
	var card := _card("骨甲圆盾", 8, 2, 1)
	var content := MonsterEventContentScript.new()
	content.mob = _mob("啮髓鼠群", 10, 2, 1, "啃食骨髓：造成 2 点伤害。", card)
	content.drop_entries = [_gold_drop(8, 1.0), _card_drop(card, 0.5)]
	var instance := _make_event("marrow_rats", EventDataScript.EventType.MONSTER, content)
	var state := instance.runtime_state as EncounterRuntimeStateScript
	state.mob_instance = content.mob.create_instance()
	state.mob_instance.stats.hp = 3
	state.mob_instance.stats.defense = 2

	var model = _formatter.build(instance)
	_expect(model is EventHoverPreviewModelScript, "monster formatter returns a preview model")
	_expect(model.visible, "unresolved monster preview is visible")
	_expect(model.title == "啮髓鼠群", "monster preview uses mob name")
	_expect(model.type_label == "残响", "monster preview uses echo type label")
	_expect(_contains_line(model.stat_lines, "生命：3 / 10"), "monster preview prefers runtime HP")
	_expect(_contains_line(model.stat_lines, "护甲：2"), "monster preview shows runtime armor")
	_expect(_contains_line(model.reward_lines, "必得：8 金币"), "monster preview shows guaranteed gold drop")
	_expect(_contains_line(model.reward_lines, "50%：骨甲圆盾"), "monster preview shows card drop probability")
	_expect(_contains_line(model.ability_lines, "啃食骨髓：造成 2 点伤害。"), "monster preview shows action description")


func _test_boss_preview_uses_boss_label_and_defense() -> void:
	var content := BossEventContentScript.new()
	content.mob = _mob("抱肋者·白角守墓鹿", 26, 3, 6, "骨角冲锋：造成 3 点伤害。")
	content.drop_entries = [_gold_drop(20, 1.0)]
	var instance := _make_event("white_horn_hart", EventDataScript.EventType.BOSS, content)

	var model = _formatter.build(instance)
	_expect(model.visible, "unresolved boss preview is visible")
	_expect(model.type_label == "BOSS", "boss preview uses boss label")
	_expect(_contains_line(model.stat_lines, "生命：26 / 26"), "boss preview shows configured HP")
	_expect(_contains_line(model.stat_lines, "护甲：6"), "boss preview shows configured armor")
	_expect(_contains_line(model.reward_lines, "必得：20 金币"), "boss preview shows boss reward")


func _test_shop_preview_filters_sold_items_and_formats_price() -> void:
	var content := ShopEventContentScript.new()
	content.items = [_shop_item(_card("已售出的短刃", 9, 3, 0)), _shop_item(_card("余温护符", 10, 2, 1))]
	var instance := _make_event("pilgrim_camp", EventDataScript.EventType.SHOP, content)
	var state := instance.runtime_state as ShopRuntimeStateScript
	state.sold_flags = [true, false]

	var model = _formatter.build(instance)
	_expect(model.visible, "unresolved shop preview is visible")
	_expect(model.type_label == "商店", "shop preview uses shop label")
	_expect(model.reward_lines.size() == 1, "shop preview only lists available items")
	_expect(_contains_line(model.reward_lines, "余温护符"), "shop preview lists available card")
	_expect(not _contains_line(model.reward_lines, "已售出的短刃"), "shop preview filters sold card")
	_expect(_contains_line(model.reward_lines, "点数 2"), "shop preview shows card points")
	_expect(_contains_line(model.reward_lines, "护甲 1"), "shop preview shows card armor")
	_expect(_contains_line(model.reward_lines, "10 金币"), "shop preview uses market price")


func _test_treasure_preview_hides_unrolled_results_and_shows_cached_options() -> void:
	var content := TreasureEventContentScript.new()
	content.gold_range = Vector2i(4, 7)
	content.card_rewards = [_card("审判骨钉", 3, 3, 0), _card("肋盾残片", 3, 0, 3)]
	var instance := _make_event("marrow_lamp", EventDataScript.EventType.TREASURE, content)

	var before_roll = _formatter.build(instance)
	_expect(before_roll.visible, "unresolved treasure preview is visible")
	_expect(_contains_line(before_roll.reward_lines, "卡牌奖励：随机"), "unrolled treasure hides card names")
	_expect(_contains_line(before_roll.reward_lines, "金币奖励：4~7 金币"), "unrolled treasure shows gold range")
	_expect(not _contains_line(before_roll.reward_lines, "审判骨钉"), "unrolled treasure does not leak card result")

	var state := instance.runtime_state as TreasureRuntimeStateScript
	state.options = [
		TreasureRewardOptionScript.card(content.card_rewards[0]),
		TreasureRewardOptionScript.gold(6),
	]
	var after_roll = _formatter.build(instance)
	_expect(_contains_line(after_roll.reward_lines, "审判骨钉"), "rolled treasure shows cached card option")
	_expect(_contains_line(after_roll.reward_lines, "金币：6"), "rolled treasure shows cached gold option")


func _test_resolved_event_is_not_visible() -> void:
	var content := MonsterEventContentScript.new()
	content.mob = _mob("已解决残响", 4, 1, 0)
	var instance := _make_event("resolved_echo", EventDataScript.EventType.MONSTER, content)
	instance.resolve()
	var model = _formatter.build(instance)
	_expect(not model.visible, "resolved event does not produce a visible preview")


func _make_event(event_id: String, event_type: int, content: EventContent) -> EventInstance:
	var data := EventDataScript.new()
	data.event_id = event_id
	data.event_type = event_type
	data.content = content
	return data.create_instance()


func _mob(
	name: String,
	hp: int,
	attack: int,
	armor: int,
	action_description: String = "",
	card_reward: CardData = null
) -> MobData:
	var stats := CombatStatsDataScript.new()
	stats.max_hp = hp
	stats.attack = attack
	stats.defense = armor
	var mob := MobDataScript.new()
	mob.mob_name = name
	mob.base_stats = stats
	if not action_description.is_empty():
		var action := MobActionScript.new()
		action.description = action_description
		mob.actions = [action]
	if card_reward != null:
		mob.card_rewards = [card_reward]
	return mob


func _gold_drop(amount: int, chance: float) -> EncounterDropEntry:
	var drop := EncounterDropEntryScript.new()
	drop.kind = EncounterDropEntryScript.Kind.GOLD
	drop.gold_amount = amount
	drop.chance = chance
	return drop


func _card_drop(card: CardData, chance: float) -> EncounterDropEntry:
	var drop := EncounterDropEntryScript.new()
	drop.kind = EncounterDropEntryScript.Kind.CARD
	drop.card_data = card
	drop.chance = chance
	return drop


func _shop_item(card: CardData) -> ShopItemData:
	var item := ShopItemDataScript.new()
	item.card_data = card
	return item


func _card(name: String, price: int, points: int, armor: int) -> CardData:
	var card := CardDataScript.new()
	card.card_name = name
	card.value = price
	card.max_points = points
	card.armor = armor
	return card


func _contains_line(lines: Array, expected: String) -> bool:
	for line in lines:
		if str(line).contains(expected):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
