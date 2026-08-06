extends SceneTree

const CoordinatorPath := "res://scripts/game/event/event_modal_coordinator.gd"
const HandScene = preload("res://scenes/game/hand.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const CardManagerScript = preload("res://scripts/game/card_manager.gd")

var _failure_count := 0
var _emitted_instance: EventInstance
var _emitted_count := 0


class FakeDragLayer:
	extends RefCounted
	var interaction_locked := false

	func set_interaction_locked(locked: bool) -> void:
		interaction_locked = locked


class FakeShopView:
	extends RefCounted
	signal purchase_requested(item_index: int)
	signal close_requested

	var last_message := ""
	var visible := false

	func set_pricing_service(_pricing: Object) -> void:
		pass

	func show_event(_instance: EventInstance, _player: PlayerData) -> void:
		visible = true

	func hide_event() -> void:
		visible = false

	func refresh() -> void:
		pass

	func show_message(message: String, _is_error := false) -> void:
		last_message = message


class FakeTreasureView:
	extends RefCounted
	signal reward_requested(option_index: int)
	signal close_requested

	var last_message := ""
	var visible := false

	func show_event(_instance: EventInstance, _options: Array[TreasureRewardOption]) -> void:
		visible = true

	func hide_event() -> void:
		visible = false

	func show_message(message: String, _is_error := false) -> void:
		last_message = message


class FakeCombatView:
	extends RefCounted
	signal settlement_confirmed

	var visible := false
	var shown_result: CombatResult

	func show_combat(_instance: EventInstance, _monster: MobInstance, result: CombatResult) -> void:
		visible = true
		shown_result = result

	func hide_combat() -> void:
		visible = false


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_shop_purchase_uses_active_event_and_grants_card_to_run_service()
	await _test_treasure_card_reward_respects_hand_capacity_without_resolving_event()
	await _test_combat_confirmation_emits_pending_result_without_mutating_encounter()
	quit(1 if _failure_count > 0 else 0)


func _test_shop_purchase_uses_active_event_and_grants_card_to_run_service() -> void:
	var fixture := _create_fixture()
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_expect(
		coordinator.configure(
			fixture.controller,
			fixture.drag_layer,
			fixture.hand_area,
			fixture.card_service,
			fixture.player,
			fixture.shop_view,
			fixture.treasure_view,
			fixture.combat_view,
			MarketPricingService.new()
		),
		"modal coordinator accepts its event dependencies"
	)
	var initial_cards: int = fixture.card_service.get_entities().size()
	coordinator.begin(fixture.shop_instance, fixture.player_stats, _empty_chain())
	fixture.shop_view.purchase_requested.emit(0)

	_expect(
		fixture.card_service.get_entities().size() == initial_cards + 1,
		"shop reward enters runtime hand"
	)
	_expect(fixture.shop_view.last_message == "购买成功。", "shop reports completed purchase")
	await _free_fixture(fixture)


func _test_treasure_card_reward_respects_hand_capacity_without_resolving_event() -> void:
	var fixture := _create_fixture()
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture)
		return
	fixture.hand_area.max_hand_size = 0
	_expect(
		coordinator.configure(
			fixture.controller,
			fixture.drag_layer,
			fixture.hand_area,
			fixture.card_service,
			fixture.player,
			fixture.shop_view,
			fixture.treasure_view,
			fixture.combat_view,
			MarketPricingService.new()
		),
		"modal coordinator configures for treasure"
	)
	coordinator.begin(fixture.treasure_instance, fixture.player_stats, _empty_chain())
	fixture.treasure_view.reward_requested.emit(0)

	_expect(not fixture.treasure_instance.is_resolved, "full hand does not consume treasure")
	_expect(
		fixture.treasure_view.last_message == "手牌已满，无法领取这张卡牌。", "treasure explains capacity failure"
	)
	await _free_fixture(fixture)


func _test_combat_confirmation_emits_pending_result_without_mutating_encounter() -> void:
	var fixture := _create_fixture()
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture)
		return
	_expect(
		coordinator.configure(
			fixture.controller,
			fixture.drag_layer,
			fixture.hand_area,
			fixture.card_service,
			fixture.player,
			fixture.shop_view,
			fixture.treasure_view,
			fixture.combat_view,
			MarketPricingService.new()
		),
		"modal coordinator configures for combat"
	)
	_emitted_instance = null
	_emitted_count = 0
	coordinator.combat_settlement_confirmed.connect(_on_combat_settlement_confirmed)
	coordinator.begin(fixture.monster_instance, fixture.player_stats, _combat_chain())
	var monster := (fixture.monster_instance.runtime_state as EncounterRuntimeState).mob_instance
	var hp_before: int = monster.stats.hp
	fixture.combat_view.settlement_confirmed.emit()
	fixture.combat_view.settlement_confirmed.emit()

	_expect(_emitted_count == 2, "failed settlement keeps confirmation available for retry")
	_expect(
		_emitted_instance == fixture.monster_instance,
		"modal exposes pending encounter for settlement"
	)
	_expect(monster.stats.hp == hp_before, "modal confirmation does not apply combat mutation")
	_expect(
		fixture.combat_view.visible, "modal keeps combat result visible until settlement applies"
	)
	_expect(
		fixture.controller.get_pending_combat_instance() == fixture.monster_instance,
		"modal keeps the combat tuple pending until settlement completes"
	)
	await _free_fixture(fixture)


func _on_combat_settlement_confirmed(instance: EventInstance, _result: CombatResult) -> void:
	_emitted_instance = instance
	_emitted_count += 1


func _create_coordinator():
	var script = ResourceLoader.load(CoordinatorPath)
	_expect(script != null, "event modal coordinator script exists")
	return script.new() if script != null else null


func _create_fixture() -> Dictionary:
	var hand_area := HandScene.instantiate() as HandArea
	root.add_child(hand_area)
	var drag_node := Node2D.new()
	root.add_child(drag_node)
	var card_manager := CardManagerScript.new()
	card_manager.card_scene = CardEntityScene
	var card_service := RunCardService.new()
	_expect(
		card_service.configure(card_manager, hand_area, drag_node),
		"fixture configures runtime card service"
	)
	var controller := EventInteractionController.new()
	controller.configure(EncounterCombatFlowCoordinator.new())
	var player := PlayerData.new()
	player.gold = 20
	var player_stats := CombatStats.new()
	player_stats.max_hp = 12
	player_stats.hp = 12

	var shop_content := ShopEventContent.new()
	shop_content.items = [_shop_item(_card(3), 5)]
	var shop_instance := _event_instance(EventData.EventType.SHOP, shop_content)

	var treasure_content := TreasureEventContent.new()
	treasure_content.card_rewards = [_card(4)]
	treasure_content.gold_range = Vector2i(2, 2)
	var treasure_instance := _event_instance(EventData.EventType.TREASURE, treasure_content)

	var monster_content := MonsterEventContent.new()
	monster_content.mob = _mob(9)
	var monster_instance := _event_instance(EventData.EventType.MONSTER, monster_content)
	var monster := (monster_instance.runtime_state as EncounterRuntimeState).mob_instance
	return {
		"hand_area": hand_area,
		"drag_node": drag_node,
		"card_service": card_service,
		"controller": controller,
		"drag_layer": FakeDragLayer.new(),
		"player": player,
		"player_stats": player_stats,
		"shop_view": FakeShopView.new(),
		"treasure_view": FakeTreasureView.new(),
		"combat_view": FakeCombatView.new(),
		"shop_instance": shop_instance,
		"treasure_instance": treasure_instance,
		"monster_instance": monster_instance,
		"monster": monster,
	}


func _event_instance(event_type: EventData.EventType, content: EventContent) -> EventInstance:
	var data := EventData.new()
	data.event_id = "modal-test-%s" % EventData.EventType.keys()[event_type].to_lower()
	data.event_type = event_type
	data.content = content
	return data.create_instance()


func _empty_chain() -> Array[CardInstance]:
	var chain: Array[CardInstance] = []
	return chain


func _combat_chain() -> Array[CardInstance]:
	var root_card := CardInstance.new(_card(12))
	root_card.card_data.card_type = CardData.CardType.ROOT
	return [root_card]


func _shop_item(card_data: CardData, value: int) -> ShopItemData:
	card_data.value = value
	var item := ShopItemData.new()
	item.card_data = card_data
	return item


func _card(damage: int) -> CardData:
	var card := CardData.new()
	card.card_type = CardData.CardType.NORMAL
	card.damage = damage
	return card


func _mob(hp: int) -> MobData:
	var data := MobData.new()
	data.mob_name = "Modal Test Echo"
	var stats := CombatStatsData.new()
	stats.max_hp = hp
	data.base_stats = stats
	return data


func _free_fixture(fixture: Dictionary) -> void:
	var service: RunCardService = fixture.card_service
	if service != null:
		service.clear()
	for key in ["hand_area", "drag_node"]:
		var node = fixture[key]
		if is_instance_valid(node):
			node.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
