class_name RunPresentationCoordinator
extends RefCounted

## Adapts run-domain signals to the hand tray, player crest and drag layer.
##
## This coordinator is intentionally presentation-only. It reads runtime state,
## forwards UI updates and preserves terminal input locks without resolving
## events, applying rewards or invoking card rules.

var _hand_area: HandArea
var _hand_tray: HandTray
var _crest: PilgrimCrestHud
var _drag_layer: DragLayer
var _player_data: PlayerData
var _player_stats: CombatStats
var _faith: FaithService

var _flow: RunFlowCoordinator
var _modal: EventModalCoordinator
var _market: PersistentMarketCoordinator
var _configured := false
var _bound := false
var _input_locked := false
var _terminal_lock := false
var _flow_state := RunFlowCoordinator.State.UNINITIALIZED


func configure(
	hand_area: HandArea,
	hand_tray: HandTray,
	crest: PilgrimCrestHud,
	drag_layer: DragLayer,
	player_data: PlayerData,
	player_stats: CombatStats,
	faith: FaithService = null
) -> bool:
	if _configured:
		return false
	if (
		hand_area == null
		or hand_tray == null
		or crest == null
		or drag_layer == null
		or player_data == null
		or player_stats == null
	):
		return false
	_hand_area = hand_area
	_hand_tray = hand_tray
	_crest = crest
	_drag_layer = drag_layer
	_player_data = player_data
	_player_stats = player_stats
	_faith = faith
	_configured = true
	_connect_presentation_signals()
	return true


func bind(
	flow: RunFlowCoordinator, modal: EventModalCoordinator, market: PersistentMarketCoordinator
) -> bool:
	if not _configured or _bound:
		return false
	if flow == null or modal == null or market == null:
		return false
	_flow = flow
	_modal = modal
	_market = market
	_bound = true
	_connect_domain_signals()
	if _flow.has_method("get_state"):
		apply_flow_state(_flow.get_state())
	return true


func sync_all() -> void:
	if not _configured:
		return
	_sync_hand_tray(_hand_area.get_card_count(), _hand_area.max_hand_size)
	_crest.set_vitality(_player_stats.hp, _player_stats.max_hp)
	if _faith != null:
		_crest.set_faith(_faith.get_faith())
	_crest.set_gold(_player_data.gold)


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
	if not _hand_area.hand_count_changed.is_connected(_on_hand_count_changed):
		_hand_area.hand_count_changed.connect(_on_hand_count_changed)
	if _faith != null and not _faith.faith_changed.is_connected(_on_faith_changed):
		_faith.faith_changed.connect(_on_faith_changed)


func _connect_domain_signals() -> void:
	if not _modal.interaction_lock_changed.is_connected(apply_lock_request):
		_modal.interaction_lock_changed.connect(apply_lock_request)
	if not _market.player_state_changed.is_connected(_on_market_player_state_changed):
		_market.player_state_changed.connect(_on_market_player_state_changed)
	if not _market.market_ready_changed.is_connected(_on_market_ready_changed):
		_market.market_ready_changed.connect(_on_market_ready_changed)
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


func _on_hand_count_changed(current_count: int, max_count: int) -> void:
	_sync_hand_tray(current_count, max_count)


func _sync_hand_tray(current_count: int, max_count: int) -> void:
	if _hand_tray != null:
		_hand_tray.set_hand_count(current_count, max_count)


func _on_faith_changed(current_faith: int) -> void:
	if _crest != null:
		_crest.set_faith(current_faith)


func _on_market_player_state_changed() -> void:
	sync_all()


func _on_market_ready_changed(_is_ready: bool) -> void:
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
