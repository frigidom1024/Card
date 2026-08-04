extends SceneTree

const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_game_manager_syncs_pilgrim_crest()
	await _test_player_hud_syncs_updates_and_status()
	quit(0 if _failure_count == 0 else 1)


func _test_game_manager_syncs_pilgrim_crest() -> void:
	var manager := await _make_game_manager()
	var hud := manager.get_node_or_null("GameplayCanvas/PilgrimCrestHud") as PilgrimCrestHud
	_expect(hud != null, "game manager owns a Pilgrim Crest HUD")
	_expect(
		hud != null and (hud.get_node("VitalityValue") as Label).text == "%d / %d" % [manager.player_stats.hp, manager.player_stats.max_hp],
		"HUD starts with runtime vitality"
	)
	_expect(
		hud != null and (hud.get_node("FaithSeal/FaithValue") as Label).text == "FAITH · 3",
		"HUD starts with runtime faith"
	)
	_expect(manager.find_child("FaithHud", true, false) == null, "legacy FaithHud is removed")
	_cleanup_manager(manager)


func _test_player_hud_syncs_updates_and_status() -> void:
	var manager := await _make_game_manager()
	var hud := manager.get_node("GameplayCanvas/PilgrimCrestHud") as PilgrimCrestHud
	var after_combat := CombatStats.new()
	after_combat.max_hp = manager.player_stats.max_hp
	after_combat.hp = manager.player_stats.hp - 4
	manager._apply_player_combat_state(after_combat)
	_expect(
		(hud.get_node("VitalityValue") as Label).text == "%d / %d" % [after_combat.hp, after_combat.max_hp],
		"HUD refreshes after combat"
	)
	manager._on_faith_changed(2)
	_expect(
		(hud.get_node("FaithSeal/FaithValue") as Label).text == "FAITH · 2",
		"HUD refreshes after faith signal"
	)
	manager.set_player_temporary_status("CURSE · BONE CHILL")
	_expect((hud.get_node("StatusRow") as Control).visible, "manager exposes temporary status")
	manager.set_player_temporary_status("")
	_expect(not (hud.get_node("StatusRow") as Control).visible, "empty manager status clears row")
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
	if not condition:
		_failure_count += 1
		push_error(message)
