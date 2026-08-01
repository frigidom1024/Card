extends Node

signal combat_started(instance: EventInstance, monster: MobInstance)
signal combat_resolved(instance: EventInstance, result: CombatResult)
signal exploration_failed(result: CombatResult)

@onready var board: Board = $Board
@onready var card_manager: Node2D = $CardManager
@onready var hand_area: HandArea = $HandManager
@onready var drag_layer: DragLayer = $DragLayer

@export var player_data: PlayerData
@export var event_lib: EventLib
var player_stats: CombatStats
var _event_placement_service := EventPlacementService.new()
var _encounter_combat_flow := EncounterCombatFlowCoordinator.new()
var _active_event: EventInstance
var _is_exploration_failed := false

# 所有玩家相关卡牌数据引用
var cards_inst: Array[CardInstance]
var card_entities: Array[CardEntity]


func _ready() -> void:
	if player_data and player_data.base_stats:
		player_stats = CombatStats.from_data(player_data.base_stats)
	else:
		push_error("GameManager is missing PlayerData.base_stats")

	# 注入 DragLayer 的区域引用
	drag_layer.board = board
	drag_layer.hand_area = hand_area
	if not board.event_triggered.is_connected(_on_board_event_triggered):
		board.event_triggered.connect(_on_board_event_triggered)

	init_player_cards()
	init_events()
	_center_layout()

	# 窗口实时缩放时重新居中（带重复连接防护）
	var viewport := get_viewport()
	if not viewport.size_changed.is_connected(_center_layout):
		viewport.size_changed.connect(_center_layout)


# 初始化玩家卡牌：创建初始卡牌并全部发到手牌区
func init_player_cards() -> void:
	var insts = card_manager.get_init_cards(5)
	cards_inst = insts

	card_entities.clear()
	for inst in insts:
		var entity = card_manager.create_card_entity(inst)
		if not entity:
			continue
		entity.drag_layer = drag_layer
		card_entities.append(entity)
		hand_area.add_card(entity)


func init_events() -> void:
	if event_lib == null:
		push_warning("GameManager is missing EventLib")
		return
	_event_placement_service.place_initial_events(event_lib, board)


## 棋盘水平居中（垂直让出底部手牌区），手牌居中贴底
func _center_layout() -> void:
	var view := get_viewport().get_visible_rect().size
	board.position = LayoutConfig.board_origin(view, board.width, board.height, board.cell_size)
	hand_area.position = LayoutConfig.hand_origin(view)


func _on_board_event_triggered(instance: EventInstance) -> void:
	if _is_exploration_failed or _active_event != null or instance == null or instance.is_resolved:
		return
	if not _is_combat_event(instance):
		return

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

	combat_resolved.emit(instance, result)
	_apply_combat_result(instance, result)


func _apply_combat_result(instance: EventInstance, result: CombatResult) -> void:
	match result.outcome:
		CombatResult.Outcome.VICTORY:
			_apply_player_combat_state(result.player_stats_after)
			_apply_monster_combat_state(instance, result.monster_stats_after)
			instance.resolve()
			_refresh_event_display(instance)
			_finish_encounter()
		CombatResult.Outcome.RETREAT:
			_clear_player_transient_state()
			_apply_monster_combat_state(instance, result.monster_stats_after)
			_apply_penalties(result.penalties)
			_finish_encounter()
		CombatResult.Outcome.DEFEAT:
			_apply_player_combat_state(result.player_stats_after)
			_clear_monster_transient_state(instance)
			_active_event = null
			_is_exploration_failed = true
			exploration_failed.emit(result)


func _is_combat_event(instance: EventInstance) -> bool:
	var event_type := instance.get_event_type()
	return event_type == EventData.EventType.MONSTER or event_type == EventData.EventType.BOSS


func _apply_player_combat_state(result_stats: CombatStats) -> void:
	if player_stats == null or result_stats == null:
		return
	player_stats.hp = result_stats.hp
	player_stats.defense = 0


func _clear_player_transient_state() -> void:
	if player_stats != null:
		player_stats.defense = 0


func _apply_monster_combat_state(instance: EventInstance, result_stats: CombatStats) -> void:
	var monster := _get_event_monster(instance)
	if monster == null or monster.stats == null or result_stats == null:
		return
	monster.stats.hp = result_stats.hp
	monster.stats.defense = 0


func _clear_monster_transient_state(instance: EventInstance) -> void:
	var monster := _get_event_monster(instance)
	if monster != null and monster.stats != null:
		monster.stats.defense = 0


func _get_event_monster(instance: EventInstance) -> MobInstance:
	if instance == null:
		return null
	var state := instance.runtime_state as EncounterRuntimeState
	return state.mob_instance if state != null else null


func _apply_penalties(penalties: Array[CombatPenalty]) -> void:
	for penalty in penalties:
		if penalty != null and penalty.type == CombatPenalty.Type.REMOVE_TAIL_CARD:
			_remove_tail_card_from_board()


func _remove_tail_card_from_board() -> void:
	if board.cards.size() <= 1:
		return
	var tail: CardEntity = board.cards.back()
	if tail == null or not board.remove_card(tail):
		return
	if tail.card_instance != null:
		tail.card_instance.cur_zone = CardInstance.ZONE.DISCARD
		cards_inst.erase(tail.card_instance)
	card_entities.erase(tail)
	tail.queue_free()


func _refresh_event_display(instance: EventInstance) -> void:
	for event_node in board.events:
		if event_node.event_instance == instance:
			event_node.refresh_display()
			return


func _finish_encounter() -> void:
	_active_event = null
	if not _is_exploration_failed:
		drag_layer.set_interaction_locked(false)
