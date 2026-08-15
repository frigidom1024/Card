extends SceneTree

const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_game_manager_syncs_game_info()
	await _test_game_info_refreshes_after_combat()
	quit(0 if _failure_count == 0 else 1)


func _test_game_manager_syncs_game_info() -> void:
	var manager := await _make_game_manager()
	var game_info := manager.get_node_or_null("GameplayCanvas/Hud/GameInfo") as GameInfo
	_expect(game_info != null, "game manager owns GameInfo inside HUD")
	if game_info != null:
		_expect(
			(game_info.get_node("HeartContainer/HealthNumber") as Label).text
			== "%d / %d" % [manager.player_stats.hp, manager.player_stats.max_hp],
			"GameInfo starts with runtime health"
		)
		_expect(
			(game_info.get_node("GoldNumber") as Label).text == str(manager.player_data.gold),
			"GameInfo starts with runtime gold"
		)
	_cleanup_manager(manager)


func _test_game_info_refreshes_after_combat() -> void:
	var manager := await _make_game_manager()
	var game_info := manager.get_node_or_null("GameplayCanvas/Hud/GameInfo") as GameInfo
	_expect(game_info != null, "combat fixture owns GameInfo")
	if game_info == null:
		_cleanup_manager(manager)
		return

	var after_combat := CombatStats.new()
	after_combat.max_hp = manager.player_stats.max_hp
	after_combat.hp = manager.player_stats.hp - 4
	var event_data := EventData.new()
	event_data.event_id = "hud-combat"
	event_data.event_type = EventData.EventType.MONSTER
	var monster_after := CombatStats.new()
	monster_after.max_hp = 1
	monster_after.hp = 0
	var result := CombatResult.new(
		CombatResult.Outcome.VICTORY,
		after_combat,
		monster_after,
		[],
		0,
		[],
		0
	)
	_expect(
		manager._encounter_resolution.apply(event_data.create_instance(), result),
		"combat result applies through encounter resolution"
	)
	_expect(
		(game_info.get_node("HeartContainer/HealthNumber") as Label).text
		== "%d / %d" % [after_combat.hp, after_combat.max_hp],
		"GameInfo refreshes health after combat"
	)
	_cleanup_manager(manager)


func _make_game_manager() -> Node:
	var manager := GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "player HUD setup configures a starting deck")
	root.add_child(manager)
	await process_frame
	return manager


func _cleanup_manager(manager: Node) -> void:
	if is_instance_valid(manager):
		manager.queue_free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
