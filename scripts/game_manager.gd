extends Node

const ExplorationCoordinatorScript := preload("res://scripts/game/exploration/exploration_coordinator.gd")
const FaithServiceScript := preload("res://scripts/player/faith_service.gd")
const MarketPriceContextScript := preload("res://scripts/game/market/market_price_context.gd")
const MarketPricingServiceScript := preload("res://scripts/game/market/market_pricing_service.gd")
const PersistentMarketStateScript := preload("res://scripts/game/market/persistent_market_state.gd")
const PersistentMarketResolverScript := preload("res://scripts/game/market/persistent_market_resolver.gd")
const RunSetupCoordinatorScript := preload("res://scripts/game/run/run_setup_coordinator.gd")

signal combat_started(instance: EventInstance, monster: MobInstance)
signal combat_resolved(instance: EventInstance, result: CombatResult)
signal exploration_failed(result: CombatResult)
signal run_initialization_failed(reason: String)
signal run_finished
signal faith_changed(current_faith: int)

@onready var gameplay_canvas: GameplayCanvas = $GameplayCanvas
@onready var board: Board = $GameplayCanvas/Board
@onready var card_manager: Node2D = $GameplayCanvas/CardManager
@onready var hand_area: HandArea = $GameplayCanvas/HandManager
@onready var hand_tray: HandTray = $GameplayCanvas/HandTray
@onready var pilgrim_crest_hud: PilgrimCrestHud = $GameplayCanvas/PilgrimCrestHud
@onready var drag_layer: DragLayer = $GameplayCanvas/DragLayer
@onready var persistent_market = $GameplayCanvas/PersistentMarket
@onready var event_modal_layer: CanvasLayer = $EventModalLayer
@onready var shop_event_view = $EventModalLayer/ShopEventView
@onready var treasure_event_view = $EventModalLayer/TreasureEventView
@onready var combat_event_view: CombatEventView = $EventModalLayer/CombatEventView

## Static base data supplied by the scene. It is duplicated before a run starts.
@export var player_data: PlayerData
@export var event_lib: EventLib
@export var exploration_config: ExplorationConfig
var starting_deck: StartingDeckData
var player_stats: CombatStats
var _exploration_coordinator: ExplorationCoordinator
var _event_interaction_controller: EventInteractionController
var _encounter_combat_flow: EncounterCombatFlowCoordinator
var _market_pricing := MarketPricingServiceScript.new()
var _shop_event_resolver: ShopEventResolver
var _persistent_market_state
var _persistent_market_resolver
var _market_rng := RandomNumberGenerator.new()
var _treasure_event_resolver := TreasureEventResolver.new()
var _treasure_rng := RandomNumberGenerator.new()
var _faith_service := FaithServiceScript.new()
var _is_exploration_failed := false
var _market_ready := false
var _run_card_service
var _run_setup

# 所有玩家相关卡牌数据引用
var cards_inst: Array[CardInstance]
var card_entities: Array[CardEntity]


## Must be called before the manager enters the scene tree.
func configure_run(preset: StartingDeckData) -> bool:
	if is_node_ready():
		push_error("GameManager.configure_run must be called before _ready")
		return false
	if preset == null or not preset.validate().is_empty():
		push_error("GameManager received an invalid StartingDeckData")
		return false
	starting_deck = preset
	return true


func _ready() -> void:
	if not _initialize_run_state():
		return

	if not hand_area.hand_count_changed.is_connected(_sync_hand_tray):
		hand_area.hand_count_changed.connect(_sync_hand_tray)
	_sync_hand_tray()

	if not _faith_service.faith_changed.is_connected(_on_faith_changed):
		_faith_service.faith_changed.connect(_on_faith_changed)
	if not _faith_service.echo_spawn_requested.is_connected(_on_echo_spawn_requested):
		_faith_service.echo_spawn_requested.connect(_on_echo_spawn_requested)
	_sync_pilgrim_crest()

	# DragLayer only owns the interaction. FaithService observes deliberate retractions.
	drag_layer.board = board
	drag_layer.hand_area = hand_area
	_setup_persistent_market()
	drag_layer.set_market_context(persistent_market, hand_tray)
	if not drag_layer.market_purchase_requested.is_connected(_on_market_purchase_requested):
		drag_layer.market_purchase_requested.connect(_on_market_purchase_requested)
	if not drag_layer.market_reclaim_requested.is_connected(_on_market_reclaim_requested):
		drag_layer.market_reclaim_requested.connect(_on_market_reclaim_requested)
	if persistent_market != null and not persistent_market.refresh_requested.is_connected(_on_market_refresh_requested):
		persistent_market.refresh_requested.connect(_on_market_refresh_requested)
	if shop_event_view != null and shop_event_view.has_method("set_pricing_service"):
		shop_event_view.set_pricing_service(_market_pricing)
	if not drag_layer.chain_retraction_confirmed.is_connected(_faith_service.resolve_confirmed_chain_retraction):
		drag_layer.chain_retraction_confirmed.connect(_faith_service.resolve_confirmed_chain_retraction)
	if _event_interaction_controller != null:
		if not _event_interaction_controller.interaction_started.is_connected(_on_controller_interaction_started):
			_event_interaction_controller.interaction_started.connect(_on_controller_interaction_started)
		if not _event_interaction_controller.interaction_finished.is_connected(_on_controller_interaction_finished):
			_event_interaction_controller.interaction_finished.connect(_on_controller_interaction_finished)
		if not _event_interaction_controller.combat_result_ready.is_connected(_on_controller_combat_result_ready):
			_event_interaction_controller.combat_result_ready.connect(_on_controller_combat_result_ready)

	if not board.card_return_requested.is_connected(_on_board_card_return_requested):
		board.card_return_requested.connect(_on_board_card_return_requested)
	if not shop_event_view.purchase_requested.is_connected(_on_shop_purchase_requested):
		shop_event_view.purchase_requested.connect(_on_shop_purchase_requested)
	if not shop_event_view.close_requested.is_connected(_on_shop_close_requested):
		shop_event_view.close_requested.connect(_on_shop_close_requested)
	if not treasure_event_view.reward_requested.is_connected(_on_treasure_reward_requested):
		treasure_event_view.reward_requested.connect(_on_treasure_reward_requested)
	if not treasure_event_view.close_requested.is_connected(_on_treasure_close_requested):
		treasure_event_view.close_requested.connect(_on_treasure_close_requested)
	if not combat_event_view.settlement_confirmed.is_connected(_on_combat_settlement_confirmed):
		combat_event_view.settlement_confirmed.connect(_on_combat_settlement_confirmed)
	_treasure_rng.randomize()

	_configure_exploration()
	_center_layout()

	# 窗口实时缩放时重新居中（带重复连接防护）
	var viewport := get_viewport()
	if not viewport.size_changed.is_connected(_center_layout):
		viewport.size_changed.connect(_center_layout)

func _sync_hand_tray(
	current_count: int = hand_area.get_card_count(),
	max_count: int = hand_area.max_hand_size
) -> void:
	if hand_tray != null:
		hand_tray.set_hand_count(current_count, max_count)

func _initialize_run_state() -> bool:
	if starting_deck == null:
		return _fail_run_initialization("GameManager is missing StartingDeckData")
	if player_data == null or player_data.base_stats == null:
		return _fail_run_initialization("GameManager is missing PlayerData.base_stats")

	_run_setup = RunSetupCoordinatorScript.new()
	if not _run_setup.configure(player_data, starting_deck, card_manager, hand_area, drag_layer):
		return _fail_run_initialization("GameManager could not configure run setup")
	if not _run_setup.initialize():
		return _fail_run_initialization(_run_setup.get_failure_reason())

	player_data = _run_setup.get_player_data()
	player_stats = _run_setup.get_player_stats()
	_run_card_service = _run_setup.get_card_service()
	_encounter_combat_flow = _run_setup.get_encounter_combat_flow()
	_event_interaction_controller = _run_setup.get_event_interaction_controller()
	# Compatibility references for existing scene consumers and integration tests.
	cards_inst = _run_card_service.get_instances()
	card_entities = _run_card_service.get_entities()
	_faith_service.configure(player_data)
	_shop_event_resolver = ShopEventResolver.new(_market_pricing)
	return true


func _fail_run_initialization(reason: String) -> bool:
	push_error(reason)
	call_deferred("_emit_run_initialization_failed", reason)
	return false


func _emit_run_initialization_failed(reason: String) -> void:
	run_initialization_failed.emit(reason)


func _on_faith_changed(current_faith: int) -> void:
	faith_changed.emit(current_faith)
	if pilgrim_crest_hud != null:
		pilgrim_crest_hud.set_faith(current_faith)


func _setup_persistent_market() -> void:
	if persistent_market == null or card_manager == null or card_manager.card_lib == null or player_data == null:
		return
	_persistent_market_state = PersistentMarketStateScript.new()
	_market_rng.randomize()
	_persistent_market_state.initialize(card_manager.card_lib, _market_rng)
	_persistent_market_resolver = PersistentMarketResolverScript.new(_market_pricing)
	persistent_market.configure(_persistent_market_state, player_data, _market_pricing)
	_market_ready = true


func _market_context():
	var context = MarketPriceContextScript.new()
	context.player = player_data
	context.market_state = _persistent_market_state
	return context


func _on_market_purchase_requested(card: CardEntity, slot_index: int) -> void:
	if not _market_ready or card == null or not is_instance_valid(card):
		return
	var result = _persistent_market_resolver.purchase(_persistent_market_state, slot_index, player_data, not hand_area.is_full(), _market_context())
	if not result.success:
		persistent_market.show_message(_market_failure_message(result.failure), true)
		return
	persistent_market.restore_offer_card(card, slot_index)
	persistent_market.refresh_display()
	if not _grant_card_to_hand(result.card_data):
		persistent_market.show_message("CARD COULD NOT BE ADDED", true)
		return
	_sync_pilgrim_crest()
	persistent_market.show_message("CARD PURCHASED", false)


func _on_market_reclaim_requested(card: CardEntity) -> void:
	if not _market_ready or card == null or not is_instance_valid(card):
		return
	if card not in card_entities or card.card_instance == null:
		return
	var result = _persistent_market_resolver.reclaim(card.card_instance.card_data, player_data, _market_context())
	if not result.success:
		persistent_market.show_message(_market_failure_message(result.failure), true)
		return
	if _run_card_service == null or not _run_card_service.forget_card(card):
		return
	drag_layer.confirm_market_reclaim(card)
	_sync_hand_tray()
	_sync_pilgrim_crest()
	persistent_market.show_message("CARD RECLAIMED · +%d GOLD" % result.gold_delta, false)


func _on_market_refresh_requested() -> void:
	if not _market_ready:
		return
	var result = _persistent_market_resolver.refresh(_persistent_market_state, player_data, _market_context())
	if not result.success:
		persistent_market.show_message(_market_failure_message(result.failure), true)
		return
	persistent_market.refresh_display()
	_sync_pilgrim_crest()
	persistent_market.show_message("MARKET REFRESHED", false)


func _market_failure_message(failure: int) -> String:
	match failure:
		PersistentMarketResolverScript.Failure.HAND_FULL:
			return "HAND FULL"
		PersistentMarketResolverScript.Failure.INSUFFICIENT_GOLD:
			return "NOT ENOUGH GOLD"
		PersistentMarketResolverScript.Failure.INVALID_CARD, PersistentMarketResolverScript.Failure.INVALID_OFFER:
			return "TRANSACTION FAILED"
		_:
			return "TRANSACTION FAILED"

func _sync_pilgrim_crest() -> void:
	if pilgrim_crest_hud == null:
		return
	if player_stats != null:
		pilgrim_crest_hud.set_vitality(player_stats.hp, player_stats.max_hp)
	pilgrim_crest_hud.set_faith(_faith_service.get_faith())
	pilgrim_crest_hud.set_gold(player_data.gold if player_data != null else 0)


func set_player_temporary_status(status_text: String) -> void:
	if pilgrim_crest_hud != null:
		pilgrim_crest_hud.set_temporary_status(status_text)


func _on_echo_spawn_requested() -> void:
	if _exploration_coordinator == null:
		push_warning("Faith consequence could not request an exploration encounter before the level was configured")
		return
	_exploration_coordinator.request_faith_echo()


## Creates the exploration facade; fog, event scheduling, and Boss pressure stay inside it.
func _configure_exploration() -> void:
	if event_lib == null or exploration_config == null:
		push_warning("GameManager is missing level exploration data")
		return
	_exploration_coordinator = ExplorationCoordinatorScript.new()
	if not _exploration_coordinator.configure(event_lib, board, exploration_config):
		push_error("GameManager could not configure exploration coordinator")
		_exploration_coordinator = null
		return
	if not board.placement_committed.is_connected(_on_board_placement_committed):
		board.placement_committed.connect(_on_board_placement_committed)
	if not _exploration_coordinator.event_interaction_requested.is_connected(_on_board_event_triggered):
		_exploration_coordinator.event_interaction_requested.connect(_on_board_event_triggered)


func _on_board_placement_committed(result: BoardPlacementResult) -> void:
	if _is_exploration_failed or _exploration_coordinator == null:
		return
	_exploration_coordinator.resolve_placement(result)


## 按固定设计坐标布置玩法内容，再统一缩放和居中玩法画布。
func _center_layout() -> void:
	# 从这里统一调整设计坐标（1920×1080）。
	var design_size := LayoutConfig.DESIGN_VIEWPORT_SIZE
	board.position = LayoutConfig.board_origin(
		design_size, board.width, board.height, board.cell_size
	)
	hand_area.position = LayoutConfig.hand_origin(design_size)

	# 以下节点当前由 game_manager.tscn 的 Inspector 负责定位。
	# 需要切回代码布局时，可在这里集中修改它们的位置。
	hand_tray.position = Vector2(283.0, 656.0)
	pilgrim_crest_hud.position = Vector2(1620.0, 28.0)

	# GameplayCanvas 负责按窗口尺寸统一缩放并居中。
	gameplay_canvas.fit_to_viewport(get_viewport().get_visible_rect().size)


func _on_board_card_return_requested(card: CardEntity) -> void:
	if _run_card_service == null:
		return
	# GUIDE 属于玩家已持有的卡；手牌已满时也不能丢弃该卡。
	if card != null and is_instance_valid(card) and card not in hand_area.cards:
		if not _run_card_service.return_existing_to_hand(card, true):
			push_error("Failed to return guide card to hand")


func _on_board_event_triggered(instance: EventInstance) -> void:
	if _is_exploration_failed or _event_interaction_controller == null or instance == null or instance.is_resolved:
		return
	if _event_interaction_controller.get_active_event() != null:
		return
	_event_interaction_controller.begin(instance, player_stats, board.get_combat_card_chain())

func _on_controller_interaction_started(instance: EventInstance) -> void:
	if instance == null:
		return
	drag_layer.set_interaction_locked(true)
	match instance.get_event_type():
		EventData.EventType.SHOP:
			_open_shop_event(instance)
		EventData.EventType.TREASURE:
			_open_treasure_event(instance)
		EventData.EventType.MONSTER, EventData.EventType.BOSS:
			combat_started.emit(instance, _get_event_monster(instance))
		_:
			push_warning("GameManager received an unsupported event type")

func _on_controller_interaction_finished(_instance: EventInstance) -> void:
	if _is_exploration_failed:
		return
	drag_layer.set_interaction_locked(false)


func _on_controller_combat_result_ready(instance: EventInstance, result: CombatResult) -> void:
	if instance == null or result == null:
		return
	_print_combat_result_detail(result)
	combat_event_view.show_combat(instance, _get_event_monster(instance), result)

func _on_combat_settlement_confirmed() -> void:
	if _event_interaction_controller == null:
		return
	var instance := _event_interaction_controller.get_pending_combat_instance()
	var result := _event_interaction_controller.get_pending_combat_result()
	if instance == null or result == null:
		return
	combat_event_view.hide_combat()
	_apply_combat_result(instance, result)
	_event_interaction_controller.confirm_combat_settlement()
	combat_resolved.emit(instance, result)

func _open_shop_event(instance: EventInstance) -> void:
	if instance.get_content() is not ShopEventContent:
		push_warning("Shop event is missing ShopEventContent")
		return
	shop_event_view.show_event(instance, player_data)

func _open_treasure_event(instance: EventInstance) -> void:
	if instance.get_content() is not TreasureEventContent:
		push_warning("Treasure event is missing TreasureEventContent")
		return
	var options := _treasure_event_resolver.ensure_options(instance, _treasure_rng)
	if options.is_empty():
		push_warning("Treasure event produced no reward options")
		return
	treasure_event_view.show_event(instance, options)

func _on_shop_purchase_requested(item_index: int) -> void:
	var active_event := _event_interaction_controller.get_active_event() if _event_interaction_controller != null else null
	if active_event == null or active_event.get_event_type() != EventData.EventType.SHOP:
		return
	if hand_area.is_full():
		shop_event_view.show_message("手牌已满，无法购买。", true)
		return

	var result := _shop_event_resolver.purchase_item(
		active_event, item_index, player_data, true, _market_context()
	)
	if not result.success:
		shop_event_view.show_message(_resolution_failure_message(result.failure), true)
		return
	if not _grant_card_to_hand(result.granted_card):
		push_error("Shop purchase succeeded but card creation failed")
		shop_event_view.show_message("卡牌创建失败。", true)
		return
	shop_event_view.refresh()
	shop_event_view.show_message("购买成功。", false)

func _on_shop_close_requested() -> void:
	if _event_interaction_controller == null or _event_interaction_controller.get_active_event() == null:
		return
	shop_event_view.hide_event()
	_event_interaction_controller.close_shop()

func _on_treasure_reward_requested(option_index: int) -> void:
	var active_event := _event_interaction_controller.get_active_event() if _event_interaction_controller != null else null
	if active_event == null or active_event.get_event_type() != EventData.EventType.TREASURE:
		return
	var options := _treasure_event_resolver.ensure_options(active_event, _treasure_rng)
	if option_index < 0 or option_index >= options.size():
		treasure_event_view.show_message("无效的奖励选项。", true)
		return
	var option := options[option_index]
	if option.kind == TreasureRewardOption.Kind.CARD and hand_area.is_full():
		treasure_event_view.show_message("手牌已满，无法领取这张卡牌。", true)
		return

	var result := _treasure_event_resolver.claim_reward(
		active_event,
		option_index,
		player_data,
		true,
		_treasure_rng
	)
	if not result.success:
		treasure_event_view.show_message(_resolution_failure_message(result.failure), true)
		return
	if result.granted_card != null and not _grant_card_to_hand(result.granted_card):
		push_error("Treasure reward succeeded but card creation failed")
		treasure_event_view.show_message("卡牌创建失败。", true)
		return
	_refresh_event_display(active_event)
	treasure_event_view.hide_event()
	_event_interaction_controller.claim_treasure(option_index)

func _on_treasure_close_requested() -> void:
	var active_event := _event_interaction_controller.get_active_event() if _event_interaction_controller != null else null
	if active_event == null or active_event.get_event_type() != EventData.EventType.TREASURE:
		return
	treasure_event_view.show_message("必须领取一项奖励后才能离开。", true)

func _grant_card_to_hand(card_data: CardData) -> bool:
	return _run_card_service != null and _run_card_service.grant_to_hand(card_data)


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


func _apply_combat_result(instance: EventInstance, result: CombatResult) -> void:
	match result.outcome:
		CombatResult.Outcome.VICTORY:
			_apply_player_combat_state(result.player_stats_after)
			_apply_monster_combat_state(instance, result.monster_stats_after)
			instance.resolve()
			if instance.get_event_type() == EventData.EventType.BOSS and _exploration_coordinator != null:
				_exploration_coordinator.dismiss_defeated_boss(instance)
			else:
				_refresh_event_display(instance)
		CombatResult.Outcome.RETREAT:
			_apply_player_combat_state(result.player_stats_after)
			_apply_monster_combat_state(
				instance, result.monster_stats_after, result.monster_action_index_after
			)
			_return_tail_card_to_hand()
			_strengthen_encounter_monster(instance)
			_refresh_event_display(instance)
		CombatResult.Outcome.DEFEAT:
			_apply_player_combat_state(result.player_stats_after)
			_clear_monster_transient_state(instance)
			_is_exploration_failed = true
			exploration_failed.emit(result)


func _apply_player_combat_state(result_stats: CombatStats) -> void:
	if player_stats == null or result_stats == null:
		return
	player_stats.hp = result_stats.hp
	player_stats.defense = 0
	_sync_pilgrim_crest()


func _clear_player_transient_state() -> void:
	if player_stats != null:
		player_stats.defense = 0


func _apply_monster_combat_state(
	instance: EventInstance, result_stats: CombatStats, action_index_after: int = -1
) -> void:
	var monster := _get_event_monster(instance)
	if monster == null or monster.stats == null or result_stats == null:
		return
	monster.stats.hp = result_stats.hp
	monster.stats.defense = 0
	if action_index_after >= 0:
		monster.action_index = action_index_after


func _clear_monster_transient_state(instance: EventInstance) -> void:
	var monster := _get_event_monster(instance)
	if monster != null and monster.stats != null:
		monster.stats.defense = 0


func _get_event_monster(instance: EventInstance) -> MobInstance:
	if instance == null:
		return null
	var state := instance.runtime_state as EncounterRuntimeState
	return state.mob_instance if state != null else null


func _strengthen_encounter_monster(instance: EventInstance) -> void:
	var monster := _get_event_monster(instance)
	if monster != null:
		monster.gain_enhancement()


func _return_tail_card_to_hand() -> void:
	if board.cards.size() <= 1:
		return
	var tail: CardEntity = board.cards.back()
	if tail == null or not board.remove_card(tail):
		return
	if _run_card_service == null or not _run_card_service.return_existing_to_hand_temporarily(tail):
		push_error("RETREAT failed to return the final card to hand")


func _refresh_event_display(instance: EventInstance) -> void:
	for event_node in board.events:
		if event_node.event_instance == instance:
			event_node.refresh_display()
			return


func _print_combat_result_detail(result: CombatResult) -> void:
	print("========== 战斗结算详细结果 ==========")
	print("结局: ", CombatResult.Outcome.keys()[result.outcome])
	print("处理卡牌数: ", result.processed_card_count)
	print("玩家最终: ", _stats_desc(result.player_stats_after))
	print("怪物最终: ", _stats_desc(result.monster_stats_after))

	print("[战斗步骤] 共 ", result.steps.size(), " 步")
	for i in result.steps.size():
		var step := result.steps[i]
		if step == null:
			print("  第 ", i + 1, " 步: (空)")
			continue
		print("  >> 第 ", i + 1, " 步 [", CombatStep.Kind.keys()[step.kind], "] ", step.source_name)
		print("      玩家: ", _stats_desc(step.player_before), " -> ", _stats_desc(step.player_after))
		print("      怪物: ", _stats_desc(step.monster_before), " -> ", _stats_desc(step.monster_after))
		for effect in step.effects:
			if effect == null:
				continue
			var effect_desc := "      效果: [%s] %s -> %s 数值 %d" % [
				CombatEffect.SourceType.keys()[effect.source_type],
				CombatEffect.Type.keys()[effect.type],
				CombatEffect.Target.keys()[effect.target],
				effect.value,
			]
			if effect.source_name != "":
				effect_desc += " (来源: %s)" % effect.source_name
			print(effect_desc)
	print("=====================================")


func _stats_desc(stats: CombatStats) -> String:
	if stats == null:
		return "null"
	return "HP %d/%d 攻 %d 防 %d" % [stats.hp, stats.max_hp, stats.attack, stats.defense]
