class_name RunSetupCoordinator
extends RefCounted

## 局内初始化协调组件
##
## 负责根据静态玩家与初始牌组创建一次游戏流程所需的隔离运行状态。
## 包括：
## - 复制 PlayerData 并创建 CombatStats
## - 配置 RunCardService、战斗流程、事件交互与进度服务
## - 使用 Card 场景在指定 HandZone 中创建初始卡牌
## - 初始化失败时统一清理所有部分创建的运行状态
##
## 不负责：
## - 游戏页面的场景组合与 Zone 注册
## - 商店、牌桌、回收区的业务逻辑
## - FaithService 等页面级服务的装配
##
## 使用方式：
## 先通过 configure() 注入玩家、牌组、Card 场景、HandZone 与唯一 DraggerLayer，
## 再调用 initialize()；成功后从 get_context() 或兼容 getter 取得运行服务。
##
## 依赖：
## RunCardService：创建并管理 Card 与 CardInstance。
## HandZone：接收初始手牌。
## DraggerLayer：绑定运行期 Card 到页面唯一拖拽协调器。
signal initialization_failed(reason: String)

const RunCardServiceScript := preload("res://scripts/game/run/run_card_service.gd")
const EventInteractionControllerScript := preload(
	"res://scripts/game/event/event_interaction_controller.gd"
)
const RunContextScript := preload("res://scripts/game/run/run_context.gd")
const RunRandomServiceScript := preload("res://scripts/game/run/run_random_service.gd")
const RunProgressionConfigScript := preload("res://scripts/game/run/run_progression_config.gd")
const RunProgressionServiceScript := preload("res://scripts/game/run/run_progression_service.gd")

var _source_player: PlayerData
var _starting_deck: StartingDeckData
var _card_scene: PackedScene
var _hand_zone: HandZone
var _drag_layer: DraggerLayer
var _progression_config: RunProgressionConfig

var _runtime_player: PlayerData
var _player_stats: CombatStats
var _card_service: RunCardService
var _encounter_combat_flow: EncounterCombatFlowCoordinator
var _event_interaction_controller: EventInteractionController
var _context: RunContext
var _failure_reason := ""


func configure(
	source_player: PlayerData,
	deck: StartingDeckData,
	card_scene: PackedScene,
	hand_zone: HandZone,
	drag_layer: DraggerLayer,
	progression_config: RunProgressionConfig = null
) -> bool:
	if (
		source_player == null
		or deck == null
		or card_scene == null
		or hand_zone == null
		or drag_layer == null
	):
		return false
	_source_player = source_player
	_starting_deck = deck
	_card_scene = card_scene
	_hand_zone = hand_zone
	_drag_layer = drag_layer
	_progression_config = progression_config
	return true


func initialize() -> bool:
	_clear_runtime_state()
	_failure_reason = ""
	if _source_player == null or _source_player.base_stats == null:
		return _fail("Run setup is missing PlayerData.base_stats")
	if _starting_deck == null or not _starting_deck.validate().is_empty():
		return _fail("Run setup is missing a valid StartingDeckData")
	if _card_scene == null or _hand_zone == null or _drag_layer == null:
		return _fail("Run setup is missing card runtime dependencies")

	var runtime_player := _source_player.duplicate(true) as PlayerData
	if runtime_player == null or runtime_player.base_stats == null:
		return _fail("Run setup could not duplicate PlayerData")
	runtime_player.faith = PlayerData.INITIAL_FAITH

	var progression_config: RunProgressionConfig = _progression_config
	if progression_config == null:
		progression_config = RunProgressionConfigScript.new()
	var progression: RunProgressionService = RunProgressionServiceScript.new()
	if not progression.configure(progression_config):
		return _fail("Run setup could not configure progression service")

	var player_stats := CombatStats.from_data(runtime_player.base_stats)
	if player_stats == null:
		return _fail("Run setup could not create runtime combat stats")

	var card_service: RunCardService = RunCardServiceScript.new()
	if not card_service.configure(_card_scene, _hand_zone, _drag_layer):
		return _fail("Run setup could not configure runtime card service", card_service)
	if not card_service.initialize_starting_deck(_starting_deck):
		return _fail("Run setup could not create configured starter cards", card_service)

	var root_card := _starting_deck.get_root_card()
	var combat_flow := EncounterCombatFlowCoordinator.new(
		_create_combat_service_for_root(root_card)
	)
	var event_interaction_controller: EventInteractionController = (
		EventInteractionControllerScript.new()
	)
	event_interaction_controller.configure(combat_flow)

	var random: RunRandomService = RunRandomServiceScript.new()
	var context: RunContext = RunContextScript.new()
	if not context.configure(
		runtime_player,
		player_stats,
		card_service,
		combat_flow,
		event_interaction_controller,
		random,
		progression
	):
		return _fail("Run setup could not configure RunContext", card_service)

	_runtime_player = runtime_player
	_player_stats = player_stats
	_card_service = card_service
	_encounter_combat_flow = combat_flow
	_event_interaction_controller = event_interaction_controller
	_context = context
	return true


func get_context() -> RunContext:
	return _context


func get_player_data() -> PlayerData:
	return _runtime_player


func get_player_stats() -> CombatStats:
	return _player_stats


func get_card_service() -> RunCardService:
	return _card_service


func get_encounter_combat_flow() -> EncounterCombatFlowCoordinator:
	return _encounter_combat_flow


func get_event_interaction_controller() -> EventInteractionController:
	return _event_interaction_controller


func get_progression() -> RunProgressionService:
	return _context.progression if _context != null else null


func get_failure_reason() -> String:
	return _failure_reason


## Extension point for future root-specific combat services.
func _create_combat_service_for_root(_root_card: CardData) -> CombatService2:
	return CombatService2.new()


func _clear_runtime_state() -> void:
	if _card_service != null:
		_card_service.clear()
	_runtime_player = null
	_player_stats = null
	_card_service = null
	_encounter_combat_flow = null
	_event_interaction_controller = null
	_context = null


func _fail(reason: String, partial_card_service: RunCardService = null) -> bool:
	if partial_card_service != null:
		partial_card_service.clear()
	_clear_runtime_state()
	_failure_reason = reason
	initialization_failed.emit(reason)
	return false
