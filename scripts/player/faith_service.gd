class_name FaithService
extends RefCounted

## Emits the current run-scoped faith after a player deliberately retracts a placed chain.
signal faith_changed(current_faith: int)
## Requests that the map layer create one normal encounter for this retraction.
signal echo_spawn_requested

var _player_data: PlayerData


func configure(player_data: PlayerData) -> void:
	_player_data = player_data


func get_player_data() -> PlayerData:
	return _player_data


func get_faith() -> int:
	return _player_data.faith if _player_data != null else 0


func resolve_manual_chain_retraction(_removed_card: CardEntity = null, _following_card_count: int = 0) -> void:
	if _player_data == null:
		return
	#暂时去掉信仰值减少机制
	#_player_data.faith -= 1
	faith_changed.emit(_player_data.faith)
	if _player_data.faith <= 0:
		echo_spawn_requested.emit()
