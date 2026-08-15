class_name CombatLinearChainFlowProvider
extends CombatFlowProvider

const ChainContainsCardConditionScript = preload("res://scripts/combat_framework/protocol/combat_chain_contains_card_condition.gd")
const BattleOutcomeScript = preload("res://scripts/combat_framework/protocol/combat_battle_outcome.gd")

enum Step {
	PLAYER_ATTACK,
	MONSTER_ATTACK,
}

var _step: Step = Step.PLAYER_ATTACK
var _batch_sequence: int = 0
var _pending_card_id: String = ""
var _pending_counter_damage: int = 0
var _pending_player_batch_id: String = ""
var _pending_monster_batch_id: String = ""


func start(_snapshot: CombatStateSnapshot) -> void:
	_step = Step.PLAYER_ATTACK
	_batch_sequence = 0
	_clear_pending_attack()


func build_next_batch(
	snapshot: CombatStateSnapshot,
	_last_result: CombatEffectBatchResult
) -> CombatEffectBatch:
	if is_finished(snapshot):
		return null
	if _step == Step.MONSTER_ATTACK:
		return _build_monster_attack(snapshot)
	return _build_player_attack(snapshot)


func on_batch_finished(
	result: CombatEffectBatchResult,
	snapshot: CombatStateSnapshot
) -> void:
	if result == null:
		return
	if result.batch_id == _pending_player_batch_id:
		if result.is_committed() and _is_monster_alive(snapshot):
			_step = Step.MONSTER_ATTACK
		else:
			_step = Step.PLAYER_ATTACK
			_clear_pending_attack()
		return
	if result.batch_id == _pending_monster_batch_id:
		_step = Step.PLAYER_ATTACK
		_clear_pending_attack()


func is_finished(snapshot: CombatStateSnapshot) -> bool:
	return BattleOutcomeScript.is_terminal(get_outcome(snapshot))


func get_outcome(snapshot: CombatStateSnapshot) -> StringName:
	if not _is_monster_alive(snapshot):
		return BattleOutcomeScript.VICTORY
	if not _is_player_alive(snapshot):
		return BattleOutcomeScript.DEFEAT
	if _select_head_card(snapshot).is_empty():
		return BattleOutcomeScript.RETREAT
	return BattleOutcomeScript.RUNNING


func _build_player_attack(snapshot: CombatStateSnapshot) -> CombatEffectBatch:
	var card_id := _select_head_card(snapshot)
	if card_id.is_empty() or not _is_monster_alive(snapshot):
		return null
	var monster_id := str(snapshot.get_value(["monster", "entity_id"], "monster"))
	var card_points := maxi(int(snapshot.get_value(["cards", card_id, "points"], 0)), 0)
	var monster_hp_before := maxi(int(snapshot.get_value(["monster", "hp"], 0)), 0)
	var effect := CombatBatchEffect.new(
		CombatEffectTypes.DAMAGE,
		_next_id("player_damage"),
		card_id,
		[monster_id],
		{"amount": card_points}
	)
	var effects: Array[CombatBatchEffect] = [effect]
	var batch := CombatBatchFactory.create_player_attack(
		_next_id("player_attack"),
		card_id,
		effects
	)
	batch.add_condition(ChainContainsCardConditionScript.new(card_id))
	batch.metadata["target_monster_id"] = monster_id
	batch.metadata["attack_points_at_round_start"] = card_points
	batch.metadata["monster_hp_before_player_attack"] = monster_hp_before
	_pending_card_id = card_id
	_pending_counter_damage = mini(card_points, monster_hp_before)
	_pending_player_batch_id = batch.batch_id
	_pending_monster_batch_id = ""
	return batch


func _build_monster_attack(snapshot: CombatStateSnapshot) -> CombatEffectBatch:
	if not _is_monster_alive(snapshot):
		return null
	if not _is_card_active(snapshot, _pending_card_id):
		_step = Step.PLAYER_ATTACK
		_clear_pending_attack()
		return _build_player_attack(snapshot)
	var monster_id := str(snapshot.get_value(["monster", "entity_id"], "monster"))
	var effect := CombatBatchEffect.new(
		CombatEffectTypes.DAMAGE,
		_next_id("monster_damage"),
		monster_id,
		[_pending_card_id],
		{"amount": _pending_counter_damage}
	)
	var effects: Array[CombatBatchEffect] = [effect]
	var batch := CombatBatchFactory.create_monster_attack(
		_next_id("monster_attack"),
		monster_id,
		effects
	)
	batch.add_condition(ChainContainsCardConditionScript.new(_pending_card_id))
	batch.metadata["target_card_id"] = _pending_card_id
	batch.metadata["counter_damage"] = _pending_counter_damage
	_pending_monster_batch_id = batch.batch_id
	return batch


func _select_head_card(snapshot: CombatStateSnapshot) -> String:
	var chain_ids: Array = snapshot.get_value(["chain", "card_ids"], []) as Array
	for index in range(chain_ids.size() - 1, -1, -1):
		var card_id := str(chain_ids[index])
		if _is_card_active(snapshot, card_id):
			return card_id
	return ""


func _is_card_active(snapshot: CombatStateSnapshot, card_id: String) -> bool:
	if card_id.is_empty():
		return false
	var chain_ids: Array = snapshot.get_value(["chain", "card_ids"], []) as Array
	if chain_ids.find(card_id) < 0:
		return false
	if not bool(snapshot.get_value(["cards", card_id, "alive"], false)):
		return false
	return int(snapshot.get_value(["cards", card_id, "points"], 0)) > 0


func _is_player_alive(snapshot: CombatStateSnapshot) -> bool:
	return bool(snapshot.get_value(["player", "alive"], false)) \
		and int(snapshot.get_value(["player", "hp"], 0)) > 0


func _is_monster_alive(snapshot: CombatStateSnapshot) -> bool:
	return bool(snapshot.get_value(["monster", "alive"], false)) \
		and int(snapshot.get_value(["monster", "hp"], 0)) > 0


func _next_id(kind: String) -> String:
	_batch_sequence += 1
	return "linear_chain:%s:%d" % [kind, _batch_sequence]


func _clear_pending_attack() -> void:
	_pending_card_id = ""
	_pending_counter_damage = 0
	_pending_player_batch_id = ""
	_pending_monster_batch_id = ""
