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
const PersistentMarketCoordinatorScript := preload(
	"res://scripts/game/market/persistent_market_coordinator.gd"
)
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
@onready var board: Board = $GameplayCanvas/Board
@onready var card_manager: Node2D = $GameplayCanvas/CardManager
@onready var hand_area: HandArea = $GameplayCanvas/HandManager
@onready var hand_tray: HandTray = $GameplayCanvas/HandTray
@onready var pilgrim_crest_hud: PilgrimCrestHud = $GameplayCanvas/PilgrimCrestHud
@onready var drag_layer: DragLayer = $GameplayCanvas/DragLayer
@onready var persistent_market = $GameplayCanvas/PersistentMarket
@onready var shop_event_view = $EventModalLayer/ShopEventView
@onready var treasure_event_view = $EventModalLayer/TreasureEventView
@onready var combat_event_view: CombatEventView = $EventModalLayer/CombatEventView
@onready var event_hover_preview: EventHoverPreview = $EventHoverPreviewLayer/EventHoverPreview

## Static base data supplied by the scene. It is duplicated before a run starts.
@export var player_data: PlayerData
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
var _persistent_market_coordinator: PersistentMarketCoordinator
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
var card_entities: Array[CardEntity]


## Must be called before the manager enters the scene tree.
func configure_run(preset: StartingDeckData) -> bool:
	if _run_configured:
		push_error("GameManager.configure_run may only be called once")
		return false
	if is_node_ready():
		push_error("GameManager.configure_run must be called before _ready")
		return false
	if preset == null or not preset.validate().is_empty():
		push_error("GameManager received an invalid StartingDeckData")
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
	if not _initialize_run_state():
		return
	if not _configure_persistent_market():
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
	if not _run_setup.configure(player_data, starting_deck, card_manager, hand_area, drag_layer, progression_config):
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
	cards_inst = _run_card_service.get_instances()
	card_entities = _run_card_service.get_entities()
	_faith_service = null # Faith progression is paused; keep the legacy field for compatibility.
	_retraction_cost_service = CardRetractionCostServiceScript.new()
	if not _retraction_cost_service.configure(_run_context.player_data):
		return _fail_run_initialization("GameManager could not configure card retraction cost")
	drag_layer.board = board
	drag_layer.hand_area = hand_area
	return true


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
	_persistent_market_coordinator = null
	_event_modal_coordinator = null
	_event_hover_preview_coordinator = null
	_placement_pipeline = null
	_run_flow = null
	_presentation = null
	cards_inst.clear()
	card_entities.clear()


func _emit_run_initialization_failed(reason: String) -> void:
	run_initialization_failed.emit(reason)


func _configure_persistent_market() -> bool:
	if (
		persistent_market == null
		or card_manager == null
		or card_manager.card_lib == null
		or _run_context == null
	):
		return _fail_run_initialization("GameManager could not configure persistent market")
	_persistent_market_coordinator = PersistentMarketCoordinatorScript.new()
	if not _persistent_market_coordinator.configure(
		persistent_market,
		card_manager.card_lib,
		_run_context.player_data,
		hand_area,
		_run_context.card_service,
		_market_pricing,
		_run_context.random.market_rng(),
		_run_context.progression
	):
		return _fail_run_initialization("GameManager could not configure persistent market")
	_persistent_market_coordinator.connect_drag_layer(drag_layer, hand_tray)
	return true


func _configure_event_modal() -> bool:
	if _run_context == null:
		return _fail_run_initialization("GameManager could not configure event modal")
	_event_modal_coordinator = EventModalCoordinatorScript.new()
	if not _event_modal_coordinator.configure(
		_run_context.event_interaction_controller,
		drag_layer,
		hand_area,
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
		Callable(self, "_sync_pilgrim_crest"),
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
	if _retraction_cost_service != null and not drag_layer.chain_retraction_confirmed.is_connected(
		_retraction_cost_service.resolve_confirmed_chain_retraction
	):
		drag_layer.chain_retraction_confirmed.connect(
			_retraction_cost_service.resolve_confirmed_chain_retraction
		)
	if not _run_flow.start():
		return _fail_run_initialization("GameManager could not start run flow")
	return true


func _configure_presentation() -> bool:
	_presentation = RunPresentationCoordinatorScript.new()
	if not _presentation.configure(
		hand_area,
		hand_tray,
		pilgrim_crest_hud,
		drag_layer,
		_run_context.player_data,
		_run_context.player_stats,
		_faith_service,
		_retraction_cost_service
	):
		return _fail_run_initialization("GameManager could not configure run presentation")
	if not _presentation.bind(_run_flow, _event_modal_coordinator, _persistent_market_coordinator):
		return _fail_run_initialization("GameManager could not bind run presentation")
	_presentation.sync_all()
	return true


func _configure_card_return_routing() -> bool:
	if _run_flow == null or board == null:
		return _fail_run_initialization("GameManager could not configure card return routing")
	if not board.card_return_requested.is_connected(_run_flow.handle_card_return_requested):
		return _fail_run_initialization("GameManager could not connect card return routing")
	return true


func _on_board_card_return_requested(card: CardEntity) -> void:
	_run_flow.handle_card_return_requested(card)


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


func set_player_temporary_status(status_text: String) -> void:
	if pilgrim_crest_hud != null:
		pilgrim_crest_hud.set_temporary_status(status_text)


## Kept as a compatibility read for existing scene consumers.
func _sync_pilgrim_crest() -> void:
	if _presentation != null:
		_presentation.sync_all()


func _refresh_event_display(instance: EventInstance) -> void:
	for event_node in board.events:
		if event_node.event_instance == instance:
			event_node.refresh_display()
			return


func _on_unsupported_modal_event(_instance: EventInstance) -> void:
	push_warning("GameManager received an unsupported event type")


## 按固定设计坐标布置玩法内容，再统一缩放和居中玩法画布。
func _center_layout() -> void:
	return
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
