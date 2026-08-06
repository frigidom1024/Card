class_name EncounterResolutionCoordinator
extends RefCounted

## Applies a confirmed encounter result to run-time state.
##
## Combat calculation remains in EncounterCombatFlowCoordinator. This class owns
## only the state transition after the player confirms a combat settlement.
signal exploration_failed(result: CombatResult)

var _board: Board
var _player_stats: CombatStats
var _player_data: PlayerData
var _card_service: RunCardService
var _on_boss_dismissed: Callable
var _on_player_state_changed: Callable
var _on_event_display_refresh: Callable
var _reward_rng: RandomNumberGenerator
var _reward_resolver := EncounterRewardResolver.new()


func configure(
	board: Board,
	player_stats: CombatStats,
	player_data: PlayerData,
	card_service: RunCardService,
	on_boss_dismissed: Callable,
	on_player_state_changed: Callable,
	on_event_display_refresh: Callable,
	reward_rng: RandomNumberGenerator
) -> bool:
	if (
		board == null
		or player_stats == null
		or player_data == null
		or card_service == null
		or not on_boss_dismissed.is_valid()
		or not on_player_state_changed.is_valid()
		or not on_event_display_refresh.is_valid()
		or reward_rng == null
	):
		return false
	_board = board
	_player_stats = player_stats
	_player_data = player_data
	_card_service = card_service
	_on_boss_dismissed = on_boss_dismissed
	_on_player_state_changed = on_player_state_changed
	_on_event_display_refresh = on_event_display_refresh
	_reward_rng = reward_rng
	return true


func apply(instance: EventInstance, result: CombatResult) -> bool:
	if (
		instance == null
		or instance.is_resolved
		or result == null
		or _board == null
		or _player_stats == null
		or _player_data == null
		or _card_service == null
		or not _on_boss_dismissed.is_valid()
		or not _on_player_state_changed.is_valid()
		or not _on_event_display_refresh.is_valid()
		or _reward_rng == null
	):
		return false
	match result.outcome:
		CombatResult.Outcome.VICTORY:
			if instance.get_event_type() == EventData.EventType.BOSS:
				if not bool(_on_boss_dismissed.call(instance)):
					return false
			_apply_player_combat_state(result.player_stats_after)
			_apply_monster_combat_state(instance, result.monster_stats_after)
			_apply_victory_rewards(instance)
			instance.resolve()
			if instance.get_event_type() != EventData.EventType.BOSS:
				_on_event_display_refresh.call(instance)
		CombatResult.Outcome.RETREAT:
			_apply_player_combat_state(result.player_stats_after)
			_apply_monster_combat_state(
				instance, result.monster_stats_after, result.monster_action_index_after
			)
			_return_tail_card_to_hand()
			_strengthen_encounter_monster(instance)
			_on_event_display_refresh.call(instance)
		CombatResult.Outcome.DEFEAT:
			_apply_player_combat_state(result.player_stats_after)
			_clear_monster_transient_state(instance)
			exploration_failed.emit(result)
		_:
			return false
	_on_player_state_changed.call()
	return true


func _apply_player_combat_state(result_stats: CombatStats) -> void:
	if result_stats == null:
		return
	_player_stats.hp = result_stats.hp
	_player_stats.defense = 0


func _apply_victory_rewards(instance: EventInstance) -> void:
	if instance == null:
		return
	var content := instance.get_content() as EncounterEventContent
	if content == null:
		return
	var rewards := _reward_resolver.resolve(content, _reward_rng)
	_player_data.gold += rewards.gold
	for card_data in rewards.cards:
		if not _card_service.grant_to_hand_temporarily(card_data):
			push_error("VICTORY failed to grant encounter reward card")


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


func _get_event_monster(instance: EventInstance) -> MobInstance:
	if instance == null:
		return null
	var state := instance.runtime_state as EncounterRuntimeState
	return state.mob_instance if state != null else null
