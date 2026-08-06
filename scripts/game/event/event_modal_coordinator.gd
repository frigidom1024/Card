class_name EventModalCoordinator
extends RefCounted

## Owns event-modal input and reward presentation for a single run.
##
## This coordinator does not apply CombatResult state. It exposes the pending
## combat tuple so EncounterResolutionCoordinator can perform that mutation.

const MarketPriceContextScript := preload("res://scripts/game/market/market_price_context.gd")

signal combat_started(instance: EventInstance, monster: MobInstance)
signal combat_settlement_confirmed(instance: EventInstance, result: CombatResult)
signal interaction_lock_changed(locked: bool)
signal unsupported_event(instance: EventInstance)
signal event_display_refresh_requested(instance: EventInstance)

var _controller: EventInteractionController
var _drag_layer
var _hand_area: HandArea
var _card_service: RunCardService
var _player: PlayerData
var _shop_view
var _treasure_view
var _combat_view
var _pricing: Object
var _shop_resolver: ShopEventResolver
var _treasure_resolver := TreasureEventResolver.new()
var _treasure_rng := RandomNumberGenerator.new()


func configure(
	controller: EventInteractionController,
	drag_layer,
	hand_area: HandArea,
	card_service: RunCardService,
	player: PlayerData,
	shop_view,
	treasure_view,
	combat_view,
	pricing: Object
) -> bool:
	if (
		controller == null
		or drag_layer == null
		or hand_area == null
		or card_service == null
		or player == null
		or shop_view == null
		or treasure_view == null
		or combat_view == null
		or pricing == null
	):
		return false
	_controller = controller
	_drag_layer = drag_layer
	_hand_area = hand_area
	_card_service = card_service
	_player = player
	_shop_view = shop_view
	_treasure_view = treasure_view
	_combat_view = combat_view
	_pricing = pricing
	_shop_resolver = ShopEventResolver.new(_pricing)
	_treasure_rng.randomize()
	_connect_signals()
	if _shop_view.has_method("set_pricing_service"):
		_shop_view.set_pricing_service(_pricing)
	return true


func begin(instance: EventInstance, player_stats: CombatStats, chain: Array[CardInstance]) -> void:
	if _controller == null or instance == null or instance.is_resolved:
		return
	_controller.begin(instance, player_stats, chain)


## Hides the result panel and exposes the pending tuple without mutating it.
func confirm_combat_settlement() -> bool:
	if _controller == null:
		return false
	var instance := _controller.get_pending_combat_instance()
	var result := _controller.get_pending_combat_result()
	if instance == null or result == null:
		return false
	combat_settlement_confirmed.emit(instance, result)
	return true


## Completes controller lifecycle only after encounter settlement was applied.
func complete_combat_settlement() -> void:
	if _controller == null:
		return
	_combat_view.hide_combat()
	_controller.confirm_combat_settlement()


## Retains the input lock after a terminal combat failure releases the normal modal lifecycle.
func lock_interaction() -> void:
	_set_interaction_lock(true)


func _connect_signals() -> void:
	if not _controller.interaction_started.is_connected(_on_interaction_started):
		_controller.interaction_started.connect(_on_interaction_started)
	if not _controller.interaction_finished.is_connected(_on_interaction_finished):
		_controller.interaction_finished.connect(_on_interaction_finished)
	if not _controller.combat_result_ready.is_connected(_on_combat_result_ready):
		_controller.combat_result_ready.connect(_on_combat_result_ready)
	if not _shop_view.purchase_requested.is_connected(_on_shop_purchase_requested):
		_shop_view.purchase_requested.connect(_on_shop_purchase_requested)
	if not _shop_view.close_requested.is_connected(_on_shop_close_requested):
		_shop_view.close_requested.connect(_on_shop_close_requested)
	if not _treasure_view.reward_requested.is_connected(_on_treasure_reward_requested):
		_treasure_view.reward_requested.connect(_on_treasure_reward_requested)
	if not _treasure_view.close_requested.is_connected(_on_treasure_close_requested):
		_treasure_view.close_requested.connect(_on_treasure_close_requested)
	if not _combat_view.settlement_confirmed.is_connected(confirm_combat_settlement):
		_combat_view.settlement_confirmed.connect(confirm_combat_settlement)


func _on_interaction_started(instance: EventInstance) -> void:
	if instance == null:
		return
	_set_interaction_lock(true)
	match instance.get_event_type():
		EventData.EventType.SHOP:
			_open_shop_event(instance)
		EventData.EventType.TREASURE:
			_open_treasure_event(instance)
		EventData.EventType.MONSTER, EventData.EventType.BOSS:
			combat_started.emit(instance, _get_event_monster(instance))
		_:
			unsupported_event.emit(instance)


func _on_interaction_finished(_instance: EventInstance) -> void:
	_set_interaction_lock(false)


func _on_combat_result_ready(instance: EventInstance, result: CombatResult) -> void:
	if instance == null or result == null:
		return
	_print_combat_result_detail(result)
	_combat_view.show_combat(instance, _get_event_monster(instance), result)


func _open_shop_event(instance: EventInstance) -> void:
	if instance.get_content() is not ShopEventContent:
		push_warning("Shop event is missing ShopEventContent")
		return
	_shop_view.show_event(instance, _player)


func _open_treasure_event(instance: EventInstance) -> void:
	if instance.get_content() is not TreasureEventContent:
		push_warning("Treasure event is missing TreasureEventContent")
		return
	var options := _treasure_resolver.ensure_options(instance, _treasure_rng)
	if options.is_empty():
		push_warning("Treasure event produced no reward options")
		return
	_treasure_view.show_event(instance, options)


func _on_shop_purchase_requested(item_index: int) -> void:
	var active_event := _controller.get_active_event() if _controller != null else null
	if active_event == null or active_event.get_event_type() != EventData.EventType.SHOP:
		return
	if _hand_area.is_full():
		_shop_view.show_message("手牌已满，无法购买。", true)
		return
	var result := _shop_resolver.purchase_item(
		active_event, item_index, _player, true, _create_price_context()
	)
	if not result.success:
		_shop_view.show_message(_resolution_failure_message(result.failure), true)
		return
	if not _card_service.grant_to_hand(result.granted_card):
		push_error("Shop purchase succeeded but card creation failed")
		_shop_view.show_message("卡牌创建失败。", true)
		return
	_shop_view.refresh()
	_shop_view.show_message("购买成功。", false)


func _on_shop_close_requested() -> void:
	if _controller == null or _controller.get_active_event() == null:
		return
	_shop_view.hide_event()
	_controller.close_shop()


func _on_treasure_reward_requested(option_index: int) -> void:
	var active_event := _controller.get_active_event() if _controller != null else null
	if active_event == null or active_event.get_event_type() != EventData.EventType.TREASURE:
		return
	var options := _treasure_resolver.ensure_options(active_event, _treasure_rng)
	if option_index < 0 or option_index >= options.size():
		_treasure_view.show_message("无效的奖励选项。", true)
		return
	var option := options[option_index]
	if option.kind == TreasureRewardOption.Kind.CARD and _hand_area.is_full():
		_treasure_view.show_message("手牌已满，无法领取这张卡牌。", true)
		return
	var result := _treasure_resolver.claim_reward(
		active_event, option_index, _player, true, _treasure_rng
	)
	if not result.success:
		_treasure_view.show_message(_resolution_failure_message(result.failure), true)
		return
	if result.granted_card != null and not _card_service.grant_to_hand(result.granted_card):
		push_error("Treasure reward succeeded but card creation failed")
		_treasure_view.show_message("卡牌创建失败。", true)
		return
	event_display_refresh_requested.emit(active_event)
	_treasure_view.hide_event()
	_controller.claim_treasure(option_index)


func _on_treasure_close_requested() -> void:
	var active_event := _controller.get_active_event() if _controller != null else null
	if active_event == null or active_event.get_event_type() != EventData.EventType.TREASURE:
		return
	_treasure_view.show_message("必须领取一项奖励后才能离开。", true)


func _create_price_context():
	var context = MarketPriceContextScript.new()
	context.player = _player
	return context


func _resolution_failure_message(failure: EventResolutionResult.Failure) -> String:
	match failure:
		EventResolutionResult.Failure.SOLD_OUT:
			return "该商品已售罄。"
		EventResolutionResult.Failure.INSUFFICIENT_GOLD:
			return "金币不足。"
		EventResolutionResult.Failure.HAND_FULL:
			return "手牌已满。"
		EventResolutionResult.Failure.INVALID_INDEX:
			return "无效的选项。"
		EventResolutionResult.Failure.ALREADY_RESOLVED:
			return "该事件已经结束。"
		_:
			return "事件结算失败。"


func _set_interaction_lock(locked: bool) -> void:
	# The scene composition root applies this request because exploration failure
	# deliberately keeps DragLayer locked after the modal lifecycle finishes.
	interaction_lock_changed.emit(locked)


func _get_event_monster(instance: EventInstance) -> MobInstance:
	if instance == null:
		return null
	var state := instance.runtime_state as EncounterRuntimeState
	return state.mob_instance if state != null else null


func _print_combat_result_detail(result: CombatResult) -> void:
	print("========== 战斗结算详细结果 ==========")
	print("结局: ", CombatResult.Outcome.keys()[result.outcome])
	print("处理卡牌数: ", result.processed_card_count)
	print("玩家最终: ", _stats_desc(result.player_stats_after))
	print("怪物最终: ", _stats_desc(result.monster_stats_after))
	print("[战斗步骤] 共 ", result.steps.size(), " 步")
	for index in result.steps.size():
		var step := result.steps[index]
		if step == null:
			print("  第 ", index + 1, " 步: (空)")
			continue
		print(
			"  >> 第 ", index + 1, " 步 [", CombatStep.Kind.keys()[step.kind], "] ", step.source_name
		)
		print("      玩家: ", _stats_desc(step.player_before), " -> ", _stats_desc(step.player_after))
		print(
			"      怪物: ", _stats_desc(step.monster_before), " -> ", _stats_desc(step.monster_after)
		)
		for effect in step.effects:
			if effect == null:
				continue
			print(
				(
					"      效果: [%s] %s -> %s 数值 %d"
					% [
						CombatEffect.SourceType.keys()[effect.source_type],
						CombatEffect.Type.keys()[effect.type],
						CombatEffect.Target.keys()[effect.target],
						effect.value,
					]
				)
			)
	print("====================================")


func _stats_desc(stats: CombatStats) -> String:
	if stats == null:
		return "(无)"
	return "HP %d/%d, 攻击 %d, 防御 %d" % [stats.hp, stats.max_hp, stats.attack, stats.defense]
