extends Node

const FaithServiceScript := preload("res://scripts/player/faith_service.gd")

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
@onready var drag_layer: DragLayer = $GameplayCanvas/DragLayer
@onready var event_modal_layer: CanvasLayer = $EventModalLayer
@onready var shop_event_view = $EventModalLayer/ShopEventView
@onready var treasure_event_view = $EventModalLayer/TreasureEventView
@onready var combat_event_view: CombatEventView = $EventModalLayer/CombatEventView

## Static base data supplied by the scene. It is duplicated before a run starts.
@export var player_data: PlayerData
@export var event_lib: EventLib
var starting_deck: StartingDeckData
var player_stats: CombatStats
var _event_placement_service := EventPlacementService.new()
var _encounter_combat_flow: EncounterCombatFlowCoordinator
var _shop_event_resolver := ShopEventResolver.new()
var _treasure_event_resolver := TreasureEventResolver.new()
var _treasure_rng := RandomNumberGenerator.new()
var _faith_rng := RandomNumberGenerator.new()
var _faith_service := FaithServiceScript.new()
var _active_event: EventInstance
var _pending_combat_instance: EventInstance
var _pending_combat_result: CombatResult
var _is_exploration_failed := false
var _faith_label: Label
var _pending_faith_echo_spawns := 0

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

	_create_faith_hud()
	if not faith_changed.is_connected(_update_faith_hud):
		faith_changed.connect(_update_faith_hud)
	if not _faith_service.faith_changed.is_connected(_on_faith_changed):
		_faith_service.faith_changed.connect(_on_faith_changed)
	if not _faith_service.echo_spawn_requested.is_connected(_on_echo_spawn_requested):
		_faith_service.echo_spawn_requested.connect(_on_echo_spawn_requested)
	_update_faith_hud(_faith_service.get_faith())

	# DragLayer only owns the interaction. FaithService observes deliberate retractions.
	drag_layer.board = board
	drag_layer.hand_area = hand_area
	if not drag_layer.manual_chain_retracted.is_connected(_faith_service.resolve_manual_chain_retraction):
		drag_layer.manual_chain_retracted.connect(_faith_service.resolve_manual_chain_retraction)
	if not board.event_triggered.is_connected(_on_board_event_triggered):
		board.event_triggered.connect(_on_board_event_triggered)
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
	_faith_rng.randomize()

	init_events()
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

	var runtime_player := player_data.duplicate(true) as PlayerData
	if runtime_player == null or runtime_player.base_stats == null:
		return _fail_run_initialization("GameManager could not duplicate PlayerData")
	player_data = runtime_player
	player_data.faith = PlayerData.INITIAL_FAITH
	_faith_service.configure(player_data)
	player_stats = CombatStats.from_data(player_data.base_stats)
	if player_stats == null:
		return _fail_run_initialization("GameManager could not create runtime combat stats")
	if not init_player_cards():
		return _fail_run_initialization("GameManager could not create configured starter cards")

	var root_card := starting_deck.get_root_card()
	_encounter_combat_flow = EncounterCombatFlowCoordinator.new(_create_combat_service_for_root(root_card))
	return true


func _fail_run_initialization(reason: String) -> bool:
	push_error(reason)
	call_deferred("_emit_run_initialization_failed", reason)
	return false


func _emit_run_initialization_failed(reason: String) -> void:
	run_initialization_failed.emit(reason)


## Extension point for future root-specific combat services.
func _create_combat_service_for_root(_root_card: CardData) -> CombatService2:
	return CombatService2.new()


# 初始化玩家卡牌：由所选预设创建完整起始牌组并全部发到手牌区。
func init_player_cards() -> bool:
	cards_inst = card_manager.create_starting_instances(starting_deck)
	if cards_inst.is_empty():
		return false

	card_entities.clear()
	for inst in cards_inst:
		var entity = card_manager.create_card_entity(inst)
		if entity == null:
			_clear_initial_player_cards()
			return false
		entity.drag_layer = drag_layer
		if not hand_area.add_card(entity):
			entity.queue_free()
			_clear_initial_player_cards()
			return false
		card_entities.append(entity)
	return true


func _create_faith_hud() -> void:
	if _faith_label != null and is_instance_valid(_faith_label):
		return
	var hud := CanvasLayer.new()
	hud.name = "FaithHud"
	hud.layer = 0
	add_child(hud)
	_faith_label = Label.new()
	_faith_label.name = "FaithLabel"
	_faith_label.position = Vector2(24, 20)
	_faith_label.add_theme_font_size_override("font_size", 24)
	_faith_label.add_theme_color_override("font_color", Color("f2d58a"))
	hud.add_child(_faith_label)


func _update_faith_hud(current_faith: int) -> void:
	if _faith_label != null and is_instance_valid(_faith_label):
		_faith_label.text = "信仰：%d" % current_faith


func _on_faith_changed(current_faith: int) -> void:
	faith_changed.emit(current_faith)


func _on_echo_spawn_requested() -> void:
	_pending_faith_echo_spawns += 1
	_try_spawn_pending_faith_echoes()


func _try_spawn_pending_faith_echoes() -> void:
	if board == null or event_lib == null:
		return
	var templates := event_lib.get_templates_of_type(EventData.EventType.MONSTER)
	if templates.is_empty():
		push_warning("Faith consequence could not find a normal monster event template")
		return
	while _pending_faith_echo_spawns > 0:
		var template := templates[_faith_rng.randi_range(0, templates.size() - 1)]
		if not _event_placement_service.place_event_instance(
			template.create_instance(), event_lib, board, _faith_rng
		):
			return
		_pending_faith_echo_spawns -= 1


func _clear_initial_player_cards() -> void:
	for entity in card_entities:
		if is_instance_valid(entity):
			entity.queue_free()
	card_entities.clear()
	cards_inst.clear()


func init_events() -> void:
	if event_lib == null:
		push_warning("GameManager is missing EventLib")
		return
	_event_placement_service.place_initial_events(event_lib, board)


## 按固定设计坐标布置玩法内容，再统一缩放和居中玩法画布
func _center_layout() -> void:
	var design_size := LayoutConfig.DESIGN_VIEWPORT_SIZE
	board.position = LayoutConfig.board_origin(
		design_size, board.width, board.height, board.cell_size
	)
	hand_area.position = LayoutConfig.hand_origin(design_size)
	gameplay_canvas.fit_to_viewport(get_viewport().get_visible_rect().size)


func _on_board_event_triggered(instance: EventInstance) -> void:
	if _is_exploration_failed or _active_event != null or instance == null or instance.is_resolved:
		return

	match instance.get_event_type():
		EventData.EventType.SHOP:
			_open_shop_event(instance)
		EventData.EventType.TREASURE:
			_open_treasure_event(instance)
		EventData.EventType.MONSTER, EventData.EventType.BOSS:
			_begin_encounter(instance)
		_:
			push_warning("GameManager received an unsupported event type")


func _begin_encounter(instance: EventInstance) -> void:
	_active_event = instance
	drag_layer.set_interaction_locked(true)
	var monster := _encounter_combat_flow.begin(instance)
	if monster == null:
		_finish_encounter()
		return

	combat_started.emit(instance, monster)
	var result := _encounter_combat_flow.resolve(
		player_stats,
		board.get_combat_card_chain(),
		monster
	)
	if result == null:
		_finish_encounter()
		return
	_print_combat_result_detail(result)
	_pending_combat_instance = instance
	_pending_combat_result = result
	combat_event_view.show_combat(instance, monster, result)


func _on_combat_settlement_confirmed() -> void:
	if _pending_combat_instance == null or _pending_combat_result == null:
		return

	var instance := _pending_combat_instance
	var result := _pending_combat_result
	combat_event_view.hide_combat()
	_pending_combat_instance = null
	_pending_combat_result = null
	_apply_combat_result(instance, result)
	combat_resolved.emit(instance, result)


func _open_shop_event(instance: EventInstance) -> void:
	if instance.get_content() is not ShopEventContent:
		push_warning("Shop event is missing ShopEventContent")
		return
	_active_event = instance
	drag_layer.set_interaction_locked(true)
	shop_event_view.show_event(instance, player_data)


func _open_treasure_event(instance: EventInstance) -> void:
	if instance.get_content() is not TreasureEventContent:
		push_warning("Treasure event is missing TreasureEventContent")
		return
	var options := _treasure_event_resolver.ensure_options(instance, _treasure_rng)
	if options.is_empty():
		push_warning("Treasure event produced no reward options")
		return
	_active_event = instance
	drag_layer.set_interaction_locked(true)
	treasure_event_view.show_event(instance, options)


func _on_shop_purchase_requested(item_index: int) -> void:
	if _active_event == null or _active_event.get_event_type() != EventData.EventType.SHOP:
		return
	if hand_area.is_full():
		shop_event_view.show_message("手牌已满，无法购买。", true)
		return

	var result := _shop_event_resolver.purchase_item(
		_active_event, item_index, player_data, true
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
	if _active_event == null or _active_event.get_event_type() != EventData.EventType.SHOP:
		return
	shop_event_view.hide_event()
	_finish_event_interaction()


func _on_treasure_reward_requested(option_index: int) -> void:
	if _active_event == null or _active_event.get_event_type() != EventData.EventType.TREASURE:
		return
	var options := _treasure_event_resolver.ensure_options(_active_event, _treasure_rng)
	if option_index < 0 or option_index >= options.size():
		treasure_event_view.show_message("无效的奖励选项。", true)
		return
	var option := options[option_index]
	if option.kind == TreasureRewardOption.Kind.CARD and hand_area.is_full():
		treasure_event_view.show_message("手牌已满，无法领取这张卡牌。", true)
		return

	var result := _treasure_event_resolver.claim_reward(
		_active_event,
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
	_refresh_event_display(_active_event)
	treasure_event_view.hide_event()
	_finish_event_interaction()


func _on_treasure_close_requested() -> void:
	if _active_event == null or _active_event.get_event_type() != EventData.EventType.TREASURE:
		return
	treasure_event_view.show_message("必须领取一项奖励后才能离开。", true)


func _grant_card_to_hand(card_data: CardData) -> bool:
	if card_data == null or hand_area.is_full():
		return false
	var card_instance := CardInstance.new(card_data)
	card_instance.cur_zone = CardInstance.ZONE.HAND
	var entity: CardEntity = card_manager.create_card_entity(card_instance)
	if entity == null:
		return false
	entity.drag_layer = drag_layer
	if not hand_area.add_card(entity):
		entity.queue_free()
		return false
	cards_inst.append(card_instance)
	card_entities.append(entity)
	return true


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
			_refresh_event_display(instance)
			_finish_encounter()
		CombatResult.Outcome.RETREAT:
			_apply_player_combat_state(result.player_stats_after)
			_apply_monster_combat_state(
				instance, result.monster_stats_after, result.monster_action_index_after
			)
			_return_tail_card_to_hand()
			_strengthen_encounter_monster(instance)
			_refresh_event_display(instance)
			_finish_encounter()
		CombatResult.Outcome.DEFEAT:
			_apply_player_combat_state(result.player_stats_after)
			_clear_monster_transient_state(instance)
			_active_event = null
			_is_exploration_failed = true
			exploration_failed.emit(result)


func _apply_player_combat_state(result_stats: CombatStats) -> void:
	if player_stats == null or result_stats == null:
		return
	player_stats.hp = result_stats.hp
	player_stats.defense = 0


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
	if tail.card_instance != null:
		tail.card_instance.cur_zone = CardInstance.ZONE.HAND
	var previous_max_hand_size := hand_area.max_hand_size
	if hand_area.is_full():
		hand_area.max_hand_size = hand_area.cards.size() + 1
	if not hand_area.add_card(tail):
		hand_area.max_hand_size = previous_max_hand_size
		push_error("RETREAT failed to return the final card to hand")
		return
	hand_area.max_hand_size = previous_max_hand_size


func _refresh_event_display(instance: EventInstance) -> void:
	for event_node in board.events:
		if event_node.event_instance == instance:
			event_node.refresh_display()
			return


func _finish_encounter() -> void:
	_finish_event_interaction()


func _finish_event_interaction() -> void:
	_active_event = null
	if not _is_exploration_failed:
		drag_layer.set_interaction_locked(false)
		_try_spawn_pending_faith_echoes()


## 调试：打印一次战斗结算的完整详细信息
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
