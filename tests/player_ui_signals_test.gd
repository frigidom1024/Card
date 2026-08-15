extends SceneTree

const GameInfoScene := preload("res://scenes/game/hud/game_info.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_player_gold_operations_publish_changes()
	_test_combat_vitality_operations_publish_changes()
	await _test_game_info_binds_and_rebinds_player_sources()
	quit(0 if _failure_count == 0 else 1)


func _test_player_gold_operations_publish_changes() -> void:
	var player := PlayerData.new()
	player.gold = 10
	if not _require_methods(player, ["add_gold", "spend_gold", "can_afford", "set_gold"]):
		return
	if not _require_signal(player, "gold_changed"):
		return

	var published_values: Array[int] = []
	player.gold_changed.connect(func(current_gold: int) -> void:
		published_values.append(current_gold)
	)

	player.add_gold(5)
	_expect(player.gold == 15, "adding gold changes the player's balance")
	_expect(published_values == [15], "adding gold publishes the new balance once")
	_expect(player.can_afford(15), "the player can afford an exact-balance purchase")
	_expect(player.spend_gold(4), "an affordable purchase succeeds")
	_expect(player.gold == 11, "spending gold deducts the requested amount")
	_expect(published_values == [15, 11], "spending gold publishes the remaining balance")
	_expect(not player.spend_gold(12), "an unaffordable purchase is rejected")
	_expect(player.gold == 11, "a rejected purchase preserves the balance")
	_expect(published_values == [15, 11], "a rejected purchase publishes no false change")
	player.set_gold(-3)
	_expect(player.gold == 0, "setting gold clamps the balance to zero")
	_expect(published_values == [15, 11, 0], "setting gold publishes the normalized balance")
	player.set_gold(0)
	_expect(published_values == [15, 11, 0], "setting the same balance publishes no duplicate")


func _test_combat_vitality_operations_publish_changes() -> void:
	var stats := CombatStats.new()
	stats.max_hp = 20
	stats.hp = 15
	if not _require_methods(stats, ["set_vitality"]):
		return
	if not _require_signal(stats, "vitality_changed"):
		return

	var published_values: Array[Vector2i] = []
	stats.vitality_changed.connect(func(current_hp: int, max_hp: int) -> void:
		published_values.append(Vector2i(current_hp, max_hp))
	)

	stats.take_damage(4)
	_expect(stats.hp == 11, "damage changes current health")
	_expect(
		published_values == [Vector2i(11, 20)],
		"damage publishes current and maximum health"
	)
	stats.heal(2)
	_expect(stats.hp == 13, "healing changes current health")
	_expect(
		published_values == [Vector2i(11, 20), Vector2i(13, 20)],
		"healing publishes current and maximum health"
	)
	stats.set_vitality(7, 25)
	_expect(stats.hp == 7 and stats.max_hp == 25, "vitality synchronization updates both values")
	_expect(
		published_values == [Vector2i(11, 20), Vector2i(13, 20), Vector2i(7, 25)],
		"vitality synchronization publishes the complete new state"
	)
	stats.take_damage(0)
	stats.heal(0)
	stats.set_vitality(7, 25)
	_expect(published_values.size() == 3, "unchanged vitality publishes no duplicate")


func _test_game_info_binds_and_rebinds_player_sources() -> void:
	var game_info := GameInfoScene.instantiate() as GameInfo
	root.add_child(game_info)
	await process_frame
	if not _require_methods(game_info, ["bind_player"]):
		game_info.queue_free()
		return

	var first_player := PlayerData.new()
	first_player.gold = 12
	var first_stats := CombatStats.new()
	first_stats.max_hp = 30
	first_stats.hp = 24
	game_info.bind_player(first_player, first_stats)
	_expect(_health_text(game_info) == "24 / 30", "binding immediately displays player vitality")
	_expect(_gold_text(game_info) == "12", "binding immediately displays player gold")

	first_player.add_gold(3)
	first_stats.take_damage(5)
	_expect(_gold_text(game_info) == "15", "GameInfo reacts to the player's gold signal")
	_expect(_health_text(game_info) == "19 / 30", "GameInfo reacts to the vitality signal")

	var second_player := PlayerData.new()
	second_player.gold = 7
	var second_stats := CombatStats.new()
	second_stats.max_hp = 18
	second_stats.hp = 16
	game_info.bind_player(second_player, second_stats)
	_expect(_health_text(game_info) == "16 / 18", "rebinding immediately displays new vitality")
	_expect(_gold_text(game_info) == "7", "rebinding immediately displays new gold")

	first_player.add_gold(10)
	first_stats.heal(10)
	_expect(_gold_text(game_info) == "7", "the previous player no longer updates GameInfo")
	_expect(_health_text(game_info) == "16 / 18", "the previous stats no longer update GameInfo")
	second_player.spend_gold(2)
	second_stats.heal(2)
	_expect(_gold_text(game_info) == "5", "the rebound player continues updating GameInfo")
	_expect(_health_text(game_info) == "18 / 18", "the rebound stats continue updating GameInfo")
	game_info.queue_free()


func _health_text(game_info: GameInfo) -> String:
	return (game_info.get_node("HeartContainer/HealthNumber") as Label).text


func _gold_text(game_info: GameInfo) -> String:
	return (game_info.get_node("GoldNumber") as Label).text


func _require_methods(target: Object, methods: Array[String]) -> bool:
	var available := true
	for method_name in methods:
		if target.has_method(method_name):
			continue
		available = false
		_expect(false, "%s provides %s()" % [target.get_class(), method_name])
	return available


func _require_signal(target: Object, signal_name: StringName) -> bool:
	var available := target.has_signal(signal_name)
	_expect(available, "%s publishes %s" % [target.get_class(), signal_name])
	return available


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
