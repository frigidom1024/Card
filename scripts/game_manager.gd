## 游戏页面组合根组件
##
## 负责装配一次运行所需的页面级服务、常驻卡牌区域与唯一拖拽协调器。
## 包括：
## - 创建隔离的运行上下文并连接探索、事件、战斗与展示协调器
## - 配置常驻 Board、HandZone、Shop 与 ReclaimZone
## - 将四个卡牌区域注册到页面唯一 DraggerLayer
## - 同步处理 Board 发出的 GUIDE 与拆链后继卡牌回手请求
##
## 不负责：
## - 各区域内部的空间判断、成员布局与拖拽事务规则
## - CardInstance 的数据持久化或 Card 的显示绘制
## - 商店补货、回收价格或牌桌格子计算
##
## 使用方式：
## 在节点进入场景树前调用 configure_run() 注入有效 StartingDeckData；
## 场景就绪后本组件自动完成运行上下文、常驻区域和页面协调器装配。
##
## 依赖：
## Board/HandZone/Shop/ReclaimZone：提供常驻玩法区域。
## DraggerLayer：协调页面内所有 CardZone 的同步原子拖拽。
## RunSetupCoordinator/RunFlowCoordinator：创建并推进一次运行。

extends Node

const ExplorationCoordinatorScript := preload(
	"res://scripts/game/exploration/exploration_coordinator.gd"
)
const CardChainCoordinatorScript := preload("res://scripts/card/card_chain_coordinator.gd")
const EncounterResolutionCoordinatorScript := preload(
	"res://scripts/game/event/encounter/encounter_resolution_coordinator.gd"
)
const FaithServiceScript := preload("res://scripts/player/faith_service.gd")
const CardRetractionCostServiceScript := preload("res://scripts/game/run/card_retraction_cost_service.gd")
const MarketPricingServiceScript := preload("res://scripts/game/market/market_pricing_service.gd")
const RunSetupCoordinatorScript := preload("res://scripts/game/run/run_setup_coordinator.gd")
const MarketPriceContextScript := preload("res://scripts/game/market/market_price_context.gd")
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const EventModalCoordinatorScript := preload("res://scripts/game/event/event_modal_coordinator.gd")
const PlacementPipelineCoordinatorScript := preload(
	"res://scripts/game/placement/placement_pipeline_coordinator.gd"
)
const RunFlowCoordinatorScript := preload("res://scripts/game/run/run_flow_coordinator.gd")
const RunPresentationCoordinatorScript := preload(
	"res://scripts/game/run/run_presentation_coordinator.gd"
)
const EventHoverPreviewCoordinatorScript := preload(
	"res://scripts/game/event/hover/event_hover_preview_coordinator.gd"
)

signal combat_started(instance: EventInstance, monster: MobInstance)
signal combat_resolved(instance: EventInstance, result: CombatResult)
signal exploration_failed(result: CombatResult)
signal run_initialization_failed(reason: String)
signal run_finished
signal faith_changed(current_faith: int)

@onready var gameplay_canvas: GameplayCanvas = $GameplayCanvas
@onready var hud: Control = $GameplayCanvas/Hud
@onready var board: Board = $GameplayCanvas/Hud/Board
@onready var hand_zone: HandZone = $GameplayCanvas/Hud/HandZone
@onready var shop: Shop = $GameplayCanvas/Hud/Shop
@onready var reclaim_zone: ReclaimZone = $GameplayCanvas/Hud/ReclaimZone
@onready var game_info: GameInfo = $GameplayCanvas/Hud/GameInfo
@onready var drag_layer: DraggerLayer = $GameplayCanvas/DragLayer
@onready var shop_event_view = $EventModalLayer/ShopEventView
@onready var treasure_event_view = $EventModalLayer/TreasureEventView
@onready var combat_event_view: CombatEventView = $EventModalLayer/CombatEventView
@onready var event_hover_preview: EventHoverPreview = $EventHoverPreviewLayer/EventHoverPreview

## Static base data supplied by the scene. It is duplicated before a run starts.
@export var player_data: PlayerData
@export var card_library: CardLibrary
@export var event_lib: EventLib
@export var exploration_config: ExplorationConfig
var starting_deck: StartingDeckData
var player_stats: CombatStats
var _run_context: RunContext
var _exploration_coordinator: ExplorationCoordinator
var _card_chain_coordinator: CardChainCoordinator
var _event_interaction_controller: EventInteractionController
var _encounter_resolution: EncounterResolutionCoordinator
var _market_pricing := MarketPricingServiceScript.new()
var _event_modal_coordinator: EventModalCoordinator
var _event_hover_preview_coordinator: EventHoverPreviewCoordinator
## Legacy faith service remains declared for scene/API compatibility but is disabled for runs.
var _faith_service: FaithService
var _retraction_cost_service: CardRetractionCostService
var _run_card_service: RunCardService
var _run_setup: RunSetupCoordinator
var _placement_pipeline: PlacementPipelineCoordinator
var _run_flow: RunFlowCoordinator
var _presentation: RunPresentationCoordinator
var _run_initialization_attempted := false
var _run_configured := false
var _run_initialized := false
var _initialization_failure_emitted := false

# 所有玩家相关卡牌数据引用
var cards_inst: Array[CardInstance]
var card_entities: Array[Card]


## Must be called before the manager enters the scene tree.
func configure_run(preset: StartingDeckData) -> bool:
	if _run_configured:
		return false
	if is_node_ready():
		return false
	if preset == null or not preset.validate().is_empty():
		return false
	starting_deck = preset
	_run_configured = true
	return true


func get_run_context() -> RunContext:
	return _run_context


func get_run_flow() -> RunFlowCoordinator:
	return _run_flow


func _ready() -> void:
	if _run_initialization_attempted:
		return
	_run_initialization_attempted = true
	if not _configure_persistent_zones():
		return
	if not _initialize_run_state():
		return
	if not _configure_shop():
		return
	if not _configure_reclaim_zone():
		return
	if not _configure_event_modal():
		return
	if not _configure_event_hover_preview():
		return
	if not _configure_card_chain():
		return
	if not _configure_exploration():
		return
	if not _configure_encounter_resolution():
		return
	if not _configure_placement_pipeline():
		return
	if not _configure_run_flow():
		return
	if not _configure_presentation():
		return
	if not _configure_card_return_routing():
		return
	_center_layout()
	_run_initialized = true


func _initialize_run_state() -> bool:
	if starting_deck == null:
		return _fail_run_initialization("GameManager is missing StartingDeckData")
	if player_data == null or player_data.base_stats == null:
		return _fail_run_initialization("GameManager is missing PlayerData.base_stats")

	_run_setup = RunSetupCoordinatorScript.new()
	var progression_config: RunProgressionConfig = exploration_config.progression_config if exploration_config != null else null
	if not _run_setup.configure(
		player_data,
		starting_deck,
		CARD_SCENE,
		hand_zone,
		drag_layer,
		progression_config
	):
		return _fail_run_initialization("GameManager could not configure run setup")
	if not _run_setup.initialize():
		return _fail_run_initialization(_run_setup.get_failure_reason())

	_run_context = _run_setup.get_context()
	if _run_context == null or not _run_context.is_valid():
		return _fail_run_initialization("GameManager could not obtain a valid RunContext")
	player_data = _run_context.player_data
	player_stats = _run_context.player_stats
	_run_card_service = _run_context.card_service
	_event_interaction_controller = _run_context.event_interaction_controller
	if not _run_card_service.cards_changed.is_connected(_sync_runtime_cards):
		_run_card_service.cards_changed.connect(_sync_runtime_cards)
	_sync_runtime_cards()
	_faith_service = null # Faith progression is paused; keep the legacy field for compatibility.
	_retraction_cost_service = CardRetractionCostServiceScript.new()
	if not _retraction_cost_service.configure(_run_context.player_data):
		return _fail_run_initialization("GameManager could not configure card retraction cost")
	return true


func _sync_runtime_cards() -> void:
	if _run_card_service == null:
		cards_inst.clear()
		card_entities.clear()
		return
	cards_inst = _run_card_service.get_instances()
	card_entities = _run_card_service.get_entities()


func _fail_run_initialization(reason: String) -> bool:
	if _initialization_failure_emitted:
		return false
	_clear_runtime_references()
	push_error(reason)
	_initialization_failure_emitted = true
	call_deferred("_emit_run_initialization_failed", reason)
	return false


func _clear_runtime_references() -> void:
	if _run_card_service != null:
		_run_card_service.clear()
	_run_context = null
	_run_setup = null
	_run_card_service = null
	_event_interaction_controller = null
	player_stats = null
	_faith_service = null
	_retraction_cost_service = null
	_exploration_coordinator = null
	_card_chain_coordinator = null
	_encounter_resolution = null
	_event_modal_coordinator = null
	_event_hover_preview_coordinator = null
	_placement_pipeline = null
	_run_flow = null
	_presentation = null
	cards_inst.clear()
	card_entities.clear()


func _emit_run_initialization_failed(reason: String) -> void:
	run_initialization_failed.emit(reason)


func _configure_persistent_zones() -> bool:
	if (
		drag_layer == null
		or hand_zone == null
		or board == null
		or board.board_zone == null
		or shop == null
		or reclaim_zone == null
	):
		return _fail_run_initialization(
			"GameManager could not configure persistent card zones"
		)
	drag_layer.register_zone(hand_zone)
	board.board_zone.set_drag_layer(drag_layer)
	shop.set_drag_layer(drag_layer)
	reclaim_zone.set_drag_layer(drag_layer)
	return true


func _configure_shop() -> bool:
	if card_library == null or shop == null or _run_context == null:
		return _fail_run_initialization("GameManager could not configure persistent shop")
	if not shop.configure(
		card_library,
		_run_context.player_data,
		_run_context.card_service,
		_market_pricing,
		_run_context.random.market_rng(),
		_run_context.progression
	):
		return _fail_run_initialization("GameManager could not configure persistent shop")
	return true


func _configure_reclaim_zone() -> bool:
	if reclaim_zone == null or _run_context == null:
		return _fail_run_initialization("GameManager could not configure ReclaimZone")
	var price_context := MarketPriceContextScript.new()
	price_context.player = _run_context.player_data
	price_context.market_state = shop
	if not reclaim_zone.configure(
		_run_context.player_data,
		_run_context.card_service,
		_market_pricing,
		price_context
	):
		return _fail_run_initialization("GameManager could not configure ReclaimZone")
	return true


func _configure_event_modal() -> bool:
	if _run_context == null:
		return _fail_run_initialization("GameManager could not configure event modal")
	_event_modal_coordinator = EventModalCoordinatorScript.new()
	if not _event_modal_coordinator.configure(
		_run_context.event_interaction_controller,
		drag_layer,
		hand_zone,
		_run_context.card_service,
		_run_context.player_data,
		shop_event_view,
		treasure_event_view,
		combat_event_view,
		_market_pricing,
		_run_context.progression
	):
		return _fail_run_initialization("GameManager could not configure event modal coordinator")
	if not _event_modal_coordinator.event_display_refresh_requested.is_connected(
		_refresh_event_display
	):
		_event_modal_coordinator.event_display_refresh_requested.connect(_refresh_event_display)
	if not _event_modal_coordinator.unsupported_event.is_connected(_on_unsupported_modal_event):
		_event_modal_coordinator.unsupported_event.connect(_on_unsupported_modal_event)
	return true


func _configure_event_hover_preview() -> bool:
	if board == null or event_hover_preview == null:
		return _fail_run_initialization("GameManager could not configure event hover preview")
	_event_hover_preview_coordinator = EventHoverPreviewCoordinatorScript.new()
	if not _event_hover_preview_coordinator.configure(board, event_hover_preview, get_viewport()):
		return _fail_run_initialization("GameManager could not bind event hover preview")
	return true


func _configure_card_chain() -> bool:
	_card_chain_coordinator = CardChainCoordinatorScript.new()
	if not _card_chain_coordinator.configure(board):
		return _fail_run_initialization("GameManager could not configure card-chain coordinator")
	return true


func _configure_exploration() -> bool:
	if event_lib == null or exploration_config == null:
		return _fail_run_initialization("GameManager is missing level exploration data")
	_exploration_coordinator = ExplorationCoordinatorScript.new()
	if not _exploration_coordinator.configure(event_lib, board, exploration_config, _run_context.progression):
		return _fail_run_initialization("GameManager could not configure exploration coordinator")
	_exploration_coordinator.initialize_events()
	return true


func _configure_encounter_resolution() -> bool:
	_encounter_resolution = EncounterResolutionCoordinatorScript.new()
	if not _encounter_resolution.configure(
		board,
		_run_context.player_stats,
		_run_context.player_data,
		_run_context.card_service,
		Callable(_exploration_coordinator, "dismiss_defeated_boss"),
		Callable(self, "_refresh_event_display"),
		_run_context.random.encounter_reward_rng()
	):
		return _fail_run_initialization("GameManager could not configure encounter resolution")
	return true


func _configure_placement_pipeline() -> bool:
	_placement_pipeline = PlacementPipelineCoordinatorScript.new()
	if not _placement_pipeline.configure(board, _card_chain_coordinator, _exploration_coordinator):
		return _fail_run_initialization("GameManager could not configure placement pipeline")
	if not _placement_pipeline.connect_board():
		return _fail_run_initialization("GameManager could not connect placement pipeline to Board")
	return true


func _configure_run_flow() -> bool:
	_run_flow = RunFlowCoordinatorScript.new()
	if not _run_flow.configure(
		_run_context,
		_placement_pipeline,
		_event_modal_coordinator,
		_encounter_resolution,
		_faith_service,
		board
	):
		return _fail_run_initialization("GameManager could not configure run flow")
	if not _run_flow.set_resolved_event_dismissal_request(
		Callable(_exploration_coordinator, "dismiss_resolved_event")
	):
		return _fail_run_initialization("GameManager could not configure resolved event cleanup")
	if not _run_flow.combat_started.is_connected(_forward_combat_started):
		_run_flow.combat_started.connect(_forward_combat_started)
	if not _run_flow.combat_resolved.is_connected(_forward_combat_resolved):
		_run_flow.combat_resolved.connect(_forward_combat_resolved)
	if not _run_flow.exploration_failed.is_connected(_forward_exploration_failed):
		_run_flow.exploration_failed.connect(_forward_exploration_failed)
	if not _run_flow.run_finished.is_connected(_forward_run_finished):
		_run_flow.run_finished.connect(_forward_run_finished)
	if _retraction_cost_service != null and not board.chain_retraction_confirmed.is_connected(
		_retraction_cost_service.resolve_confirmed_chain_retraction
	):
		board.chain_retraction_confirmed.connect(
			_retraction_cost_service.resolve_confirmed_chain_retraction
		)
	if not _run_flow.start():
		return _fail_run_initialization("GameManager could not start run flow")
	return true


func _configure_presentation() -> bool:
	_presentation = RunPresentationCoordinatorScript.new()
	if not _presentation.configure(
		game_info,
		drag_layer,
		_run_context.player_data,
		_run_context.player_stats
	):
		return _fail_run_initialization("GameManager could not configure run presentation")
	if not _presentation.bind(_run_flow, _event_modal_coordinator):
		return _fail_run_initialization("GameManager could not bind run presentation")
	return true


func _configure_card_return_routing() -> bool:
	if board == null or hand_zone == null:
		return _fail_run_initialization("GameManager could not configure card return routing")
	if not board.card_return_requested.is_connected(_on_board_card_return_requested):
		board.card_return_requested.connect(_on_board_card_return_requested)
	return true


func _on_board_card_return_requested(card: Card) -> void:
	if card == null or not is_instance_valid(card) or not hand_zone.add_card(card, true):
		push_error("GameManager failed to return Card to HandZone")


func _forward_combat_started(instance: EventInstance, monster: MobInstance) -> void:
	combat_started.emit(instance, monster)


func _forward_combat_resolved(instance: EventInstance, result: CombatResult) -> void:
	combat_resolved.emit(instance, result)


func _forward_exploration_failed(result: CombatResult) -> void:
	exploration_failed.emit(result)


func _forward_run_finished() -> void:
	run_finished.emit()


func _forward_faith_changed(current_faith: int) -> void:
	faith_changed.emit(current_faith)


func _refresh_event_display(instance: EventInstance) -> void:
	for event_node: BoardEvent in board.event_zone.get_events():
		if event_node.event_instance == instance:
			event_node.refresh_display()
			return


func _on_unsupported_modal_event(_instance: EventInstance) -> void:
	push_warning("GameManager received an unsupported event type")


## 页面区域使用场景中保存的 1920×1080 设计坐标；缩放由 GameplayCanvas 统一处理。
func _center_layout() -> void:
	gameplay_canvas.fit_to_viewport(get_viewport().get_visible_rect().size)
