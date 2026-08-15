## 运行展示协调组件
##
## 负责把运行期状态与领域信号同步到玩家信息面板和页面输入锁。
## 包括：
## - 生命与金币的展示同步
## - 普通事件与终局状态的拖拽锁同步
##
## 不负责：
## - 卡牌创建、移动或区域规则
## - 商店、事件奖励与战斗结果的业务结算
## - 运行流程状态的推进
##
## 使用方式：
## 先通过 configure() 注入展示节点与运行数据，再通过 bind() 订阅 RunFlowCoordinator
## 和 EventModalCoordinator，最后调用 sync_all() 完成首次刷新。
##
## 依赖：
## GameInfo：显示生命与金币。
## DraggerLayer：应用页面交互锁。
## RunFlowCoordinator/EventModalCoordinator：发布运行与弹窗状态。

class_name RunPresentationCoordinator
extends RefCounted

var _game_info: GameInfo
var _drag_layer: DraggerLayer
var _player_data: PlayerData
var _player_stats: CombatStats
var _retraction_cost: CardRetractionCostService

var _flow: RunFlowCoordinator
var _modal: EventModalCoordinator
var _configured := false
var _bound := false
var _input_locked := false
var _terminal_lock := false
var _flow_state := RunFlowCoordinator.State.UNINITIALIZED


func configure(
	game_info: GameInfo,
	drag_layer: DraggerLayer,
	player_data: PlayerData,
	player_stats: CombatStats,
	retraction_cost: CardRetractionCostService = null
) -> bool:
	if _configured:
		return false
	if (
		game_info == null
		or drag_layer == null
		or player_data == null
		or player_stats == null
	):
		return false
	_game_info = game_info
	_drag_layer = drag_layer
	_player_data = player_data
	_player_stats = player_stats
	_retraction_cost = retraction_cost
	_configured = true
	_connect_presentation_signals()
	return true


func bind(flow: RunFlowCoordinator, modal: EventModalCoordinator) -> bool:
	if not _configured or _bound:
		return false
	if flow == null or modal == null:
		return false
	_flow = flow
	_modal = modal
	_bound = true
	_connect_domain_signals()
	if _flow.has_method("get_state"):
		apply_flow_state(_flow.get_state())
	return true


func sync_all() -> void:
	if not _configured:
		return
	_game_info.set_vitality(_player_stats.hp, _player_stats.max_hp)
	_game_info.set_gold(_player_data.gold)


func apply_lock_request(locked: bool) -> void:
	if not _configured:
		return
	if not locked and _is_terminal_state():
		locked = true
	_input_locked = locked
	_drag_layer.set_interaction_locked(locked)


func is_input_locked() -> bool:
	return _input_locked


func apply_flow_state(state: RunFlowCoordinator.State) -> void:
	_flow_state = state
	if state == RunFlowCoordinator.State.FAILED or state == RunFlowCoordinator.State.FINISHED:
		_terminal_lock = true
	if _is_terminal_state():
		apply_lock_request(true)


func _connect_presentation_signals() -> void:
	if (
		_retraction_cost != null
		and not _retraction_cost.retraction_cost_paid.is_connected(_on_retraction_cost_paid)
	):
		_retraction_cost.retraction_cost_paid.connect(_on_retraction_cost_paid)


func _connect_domain_signals() -> void:
	if not _modal.interaction_lock_changed.is_connected(apply_lock_request):
		_modal.interaction_lock_changed.connect(apply_lock_request)
	if not _modal.non_combat_interaction_finished.is_connected(_on_non_combat_finished):
		_modal.non_combat_interaction_finished.connect(_on_non_combat_finished)
	if not _flow.combat_resolved.is_connected(_on_combat_resolved):
		_flow.combat_resolved.connect(_on_combat_resolved)
	if not _flow.exploration_failed.is_connected(_on_flow_failed):
		_flow.exploration_failed.connect(_on_flow_failed)
	if not _flow.run_finished.is_connected(_on_flow_finished):
		_flow.run_finished.connect(_on_flow_finished)
	_connect_optional_signal(_flow, "input_lock_changed", _on_flow_lock_request)
	_connect_optional_signal(_flow, "interaction_lock_changed", _on_flow_lock_request)
	_connect_optional_signal(_flow, "input_lock_requested", _on_flow_lock_request)
	_connect_optional_signal(_flow, "state_changed", _on_flow_state_changed)


func _connect_optional_signal(source: Object, signal_name: String, callback: Callable) -> void:
	if source == null or not source.has_signal(signal_name):
		return
	var signal_ref = source.get(signal_name)
	if not signal_ref.is_connected(callback):
		signal_ref.connect(callback)



func _on_retraction_cost_paid(_cost: int, _returned_count: int, remaining_gold: int) -> void:
	if _game_info != null:
		_game_info.set_gold(remaining_gold)


func _on_non_combat_finished(_instance: EventInstance) -> void:
	sync_all()


func _on_combat_resolved(_instance: EventInstance, _result: CombatResult) -> void:
	sync_all()


func _on_flow_failed(_result: CombatResult) -> void:
	apply_flow_state(RunFlowCoordinator.State.FAILED)


func _on_flow_finished() -> void:
	apply_flow_state(RunFlowCoordinator.State.FINISHED)


func _on_flow_lock_request(locked: bool) -> void:
	apply_lock_request(locked)


func _on_flow_state_changed(state: RunFlowCoordinator.State) -> void:
	apply_flow_state(state)


func _is_terminal_state() -> bool:
	return (
		_terminal_lock
		or _flow_state == RunFlowCoordinator.State.FAILED
		or _flow_state == RunFlowCoordinator.State.FINISHED
	)
