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
## 先通过 configure() 注入展示节点与运行数据，GameInfo 会绑定玩家数据信号并立即刷新；
## 再通过 bind() 订阅 RunFlowCoordinator 和 EventModalCoordinator 的输入锁与终局状态。
##
## 依赖：
## GameInfo：监听玩家数据并显示生命与金币。
## DraggerLayer：应用页面交互锁。
## RunFlowCoordinator/EventModalCoordinator：发布输入锁与终局状态。

class_name RunPresentationCoordinator
extends RefCounted

var _game_info: GameInfo
var _drag_layer: DraggerLayer

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
	player_stats: CombatStats
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
	_game_info.bind_player(player_data, player_stats)
	_configured = true
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


func _connect_domain_signals() -> void:
	if not _modal.interaction_lock_changed.is_connected(apply_lock_request):
		_modal.interaction_lock_changed.connect(apply_lock_request)
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
