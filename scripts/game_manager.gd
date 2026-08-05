extends Node

const ExplorationCoordinatorScript := preload("res://scripts/game/exploration/exploration_coordinator.gd")
const EncounterResolutionCoordinatorScript := preload("res://scripts/game/event/encounter/encounter_resolution_coordinator.gd")
const FaithServiceScript := preload("res://scripts/player/faith_service.gd")
const MarketPricingServiceScript := preload("res://scripts/game/market/market_pricing_service.gd")
const RunSetupCoordinatorScript := preload("res://scripts/game/run/run_setup_coordinator.gd")
const PersistentMarketCoordinatorScript := preload("res://scripts/game/market/persistent_market_coordinator.gd")
const EventModalCoordinatorScript := preload("res://scripts/game/event/event_modal_coordinator.gd")

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

## Static base data supplied by the scene. It is duplicated before a run starts.
@export var player_data: PlayerData
@export var event_lib: EventLib
@export var exploration_config: ExplorationConfig
var starting_deck: StartingDeckData
var player_stats: CombatStats
var _exploration_coordinator: ExplorationCoordinator
var _event_interaction_controller: EventInteractionController
var _encounter_combat_flow: EncounterCombatFlowCoordinator
var _encounter_resolution
var _market_pricing := MarketPricingServiceScript.new()
var _persistent_market_coordinator
var _event_modal_coordinator
var _market_rng := RandomNumberGenerator.new()
var _faith_service := FaithServiceScript.new()
var _is_exploration_failed := false
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
	_configure_persistent_market()
	if _persistent_market_coordinator != null:
		_persistent_market_coordinator.connect_drag_layer(drag_layer, hand_tray)
	_configure_event_modal()
	if not drag_layer.chain_retraction_confirmed.is_connected(_faith_service.resolve_confirmed_chain_retraction):
		drag_layer.chain_retraction_confirmed.connect(_faith_service.resolve_confirmed_chain_retraction)
	if not board.card_return_requested.is_connected(_on_board_card_return_requested):
		board.card_return_requested.connect(_on_board_card_return_requested)

	_configure_exploration()
	_configure_encounter_resolution()
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


func _configure_persistent_market() -> void:
	if persistent_market == null or card_manager == null or card_manager.card_lib == null or player_data == null:
		return
	_market_rng.randomize()
	_persistent_market_coordinator = PersistentMarketCoordinatorScript.new()
	if not _persistent_market_coordinator.configure(
		persistent_market,
		card_manager.card_lib,
		player_data,
		hand_area,
		_run_card_service,
		_market_pricing,
		_market_rng
	):
		push_error("GameManager could not configure persistent market")
		return
	if not _persistent_market_coordinator.player_state_changed.is_connected(_sync_pilgrim_crest):
		_persistent_market_coordinator.player_state_changed.connect(_sync_pilgrim_crest)


func _configure_event_modal() -> void:
	if _event_interaction_controller == null or _run_card_service == null:
		return
	_event_modal_coordinator = EventModalCoordinatorScript.new()
	if not _event_modal_coordinator.configure(
		_event_interaction_controller,
		drag_layer,
		hand_area,
		_run_card_service,
		player_data,
		shop_event_view,
		treasure_event_view,
		combat_event_view,
		_market_pricing
	):
		push_error("GameManager could not configure event modal coordinator")
		return
	if not _event_modal_coordinator.combat_started.is_connected(_forward_combat_started):
		_event_modal_coordinator.combat_started.connect(_forward_combat_started)
	if not _event_modal_coordinator.combat_settlement_confirmed.is_connected(_on_modal_combat_settlement_confirmed):
		_event_modal_coordinator.combat_settlement_confirmed.connect(_on_modal_combat_settlement_confirmed)
	if not _event_modal_coordinator.interaction_lock_changed.is_connected(_on_modal_interaction_lock_changed):
		_event_modal_coordinator.interaction_lock_changed.connect(_on_modal_interaction_lock_changed)
	if not _event_modal_coordinator.event_display_refresh_requested.is_connected(_refresh_event_display):
		_event_modal_coordinator.event_display_refresh_requested.connect(_refresh_event_display)
	if not _event_modal_coordinator.unsupported_event.is_connected(_on_unsupported_modal_event):
		_event_modal_coordinator.unsupported_event.connect(_on_unsupported_modal_event)


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


## Configures confirmed combat result application without coupling it to modal UI.
func _configure_encounter_resolution() -> void:
	if _encounter_resolution == null:
		_encounter_resolution = EncounterResolutionCoordinatorScript.new()
	if not _encounter_resolution.configure(
		board,
		player_stats,
		_run_card_service,
		_exploration_coordinator,
		Callable(self, "_sync_pilgrim_crest")
	):
		push_error("GameManager could not configure encounter resolution")
		return
	if not _encounter_resolution.exploration_failed.is_connected(_on_encounter_exploration_failed):
		_encounter_resolution.exploration_failed.connect(_on_encounter_exploration_failed)


func _on_encounter_exploration_failed(result: CombatResult) -> void:
	_is_exploration_failed = true
	exploration_failed.emit(result)


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
	if _is_exploration_failed or _event_modal_coordinator == null or instance == null or instance.is_resolved:
		return
	_event_modal_coordinator.begin(instance, player_stats, board.get_combat_card_chain())


func _forward_combat_started(instance: EventInstance, monster: MobInstance) -> void:
	combat_started.emit(instance, monster)


func _on_modal_interaction_lock_changed(locked: bool) -> void:
	if not locked and _is_exploration_failed:
		return
	drag_layer.set_interaction_locked(locked)


func _on_modal_combat_settlement_confirmed(instance: EventInstance, result: CombatResult) -> void:
	if instance == null or result == null:
		return
	# Keep the resolver aligned with any runtime player-stat replacement (for example, restart/debug setup).
	_configure_encounter_resolution()
	if _encounter_resolution == null or not _encounter_resolution.apply(instance, result):
		return
	_event_modal_coordinator.complete_combat_settlement()
	combat_resolved.emit(instance, result)


func _on_unsupported_modal_event(_instance: EventInstance) -> void:
	push_warning("GameManager received an unsupported event type")


func _refresh_event_display(instance: EventInstance) -> void:
	for event_node in board.events:
		if event_node.event_instance == instance:
			event_node.refresh_display()
			return
