extends SceneTree

const COORDINATOR_PATH := "res://scripts/game/market/persistent_market_coordinator.gd"
const GAME_MANAGER_SCENE := preload("res://scenes/game/game_manager.tscn")
const REVIVAL_DECK := preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_legacy_coordinator_is_an_explicit_retired_shell()
	await _test_active_page_uses_resident_shop_and_reclaim_components()
	quit(1 if _failure_count > 0 else 0)


func _test_legacy_coordinator_is_an_explicit_retired_shell() -> void:
	var coordinator_script := ResourceLoader.load(COORDINATOR_PATH)
	_expect(coordinator_script != null, "retired persistent market coordinator remains loadable")
	if coordinator_script == null:
		return
	var coordinator = coordinator_script.new()
	_expect(coordinator != null, "retired persistent market coordinator can be instantiated safely")
	if coordinator != null:
		_expect(coordinator.is_retired(), "persistent market coordinator declares its retired status")


func _test_active_page_uses_resident_shop_and_reclaim_components() -> void:
	var manager := GAME_MANAGER_SCENE.instantiate()
	_expect(manager != null, "GameManager scene instantiates")
	if manager == null:
		return
	_expect(manager.configure_run(REVIVAL_DECK), "GameManager accepts a valid starting deck")
	root.add_child(manager)
	await process_frame

	_expect(
		manager.get_node_or_null("GameplayCanvas/PersistentMarket") == null,
		"active page does not instantiate the legacy PersistentMarket"
	)
	_expect(
		manager.get_node_or_null("GameplayCanvas/Hud/Shop") is Shop,
		"active page delegates market management to the resident Shop"
	)
	_expect(
		manager.get_node_or_null("GameplayCanvas/Hud/ReclaimZone") is ReclaimZone,
		"active page delegates reclaim interaction to the resident ReclaimZone"
	)
	var manager_source := FileAccess.get_file_as_string("res://scripts/game_manager.gd")
	_expect(
		not manager_source.contains("PersistentMarketCoordinator"),
		"GameManager does not construct or retain the retired coordinator"
	)

	manager.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
