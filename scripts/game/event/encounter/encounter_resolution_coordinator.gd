class_name EncounterResolutionCoordinator
extends RefCounted

## Applies a confirmed encounter result to run-time state.
##
## Combat calculation remains in EncounterCombatFlowCoordinator. This class owns
## only the state transition after the player confirms a combat settlement.
signal exploration_failed(result: CombatResult)

var _board: Board
var _player_stats: CombatStats
var _card_service: RunCardService
var _exploration: ExplorationCoordinator
var _on_player_state_changed: Callable


func configure(
	board: Board,
	player_stats: CombatStats,
	card_service: RunCardService,
	exploration: ExplorationCoordinator,
	on_player_state_changed: Callable
) -> bool:
	if board == null or player_stats == null or card_service == null or exploration == null or not on_player_state_changed.is_valid():
		return false
	_board = board
	_player_stats = player_stats
	_card_service = card_service
	_exploration = exploration
	_on_player_state_changed = on_player_state_changed
	return true


func apply(instance: EventInstance, result: CombatResult) -> bool:
	if instance == null or result == null or _board == null or _player_stats == null:
		return false
	match result.outcome:
		CombatResult.Outcome.VICTORY:
			_apply_player_combat_state(result.player_stats_after)
			_apply_monster_combat_state(instance, result.monster_stats_after)
			instance.resolve()
			if instance.get_event_type() == EventData.EventType.BOSS:
				_exploration.dismiss_defeated_boss(instance)
			else:
				_refresh_event_display(instance)
		CombatResult.Outcome.RETREAT:
			_apply_player_combat_state(result.player_stats_after)
			_apply_monster_combat_state(instance, result.monster_stats_after, result.monster_action_index_after)
			_return_tail_card_to_hand()
			_strengthen_encounter_monster(instance)
			_refresh_event_display(instance)
		CombatResult.Outcome.DEFEAT:
			_apply_player_combat_state(result.player_stats_after)
			_clear_monster_transient_state(instance)
			exploration_failed.emit(result)
		_:
			return false
	return true


func _apply_player_combat_state(result_stats: CombatStats) -> void:
	if result_stats == null:
		return
	_player_stats.hp = result_stats.hp
	_player_stats.defense = 0
	_on_player_state_changed.call()


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


func _strengthen_encounter_monster(instance: EventInstance) -> void:
	var monster := _get_event_monster(instance)
	if monster != null:
		monster.gain_enhancement()


func _return_tail_card_to_hand() -> void:
	if _board.cards.size() <= 1:
		return
	var tail: CardEntity = _board.cards.back()
	if tail == null or not _board.remove_card(tail):
		return
	if not _card_service.return_existing_to_hand_temporarily(tail):
		push_error("RETREAT failed to return the final card to hand")


func _refresh_event_display(instance: EventInstance) -> void:
	for event_node in _board.events:
		if event_node.event_instance == instance:
			event_node.refresh_display()
			return


func _get_event_monster(instance: EventInstance) -> MobInstance:
	if instance == null:
		return null
	var state := instance.runtime_state as EncounterRuntimeState
	return state.mob_instance if state != null else null
