extends SceneTree

const GAME_MANAGER_SCENE := preload("res://scenes/game/game_manager.tscn")
const REVIVAL_DECK := preload("res://data/starting_decks/revival_starting_deck.tres")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_active_page_has_one_drag_layer_and_persistent_zones()
	await _test_all_card_zones_share_the_same_drag_layer()
	await _test_board_return_has_one_page_handler()
	await _test_active_page_excludes_legacy_zone_composition()
	quit(1 if _failures > 0 else 0)


func _test_active_page_has_one_drag_layer_and_persistent_zones() -> void:
	var page := await _create_page()
	if page == null:
		return
	_expect(page.get_node_or_null("GameplayCanvas/DragLayer") is DraggerLayer,
		"active page uses the new DraggerLayer")
	_expect(page.get_node_or_null("GameplayCanvas/Hud/Board") is Board,
		"active page contains the Board component")
	_expect(page.get_node_or_null("GameplayCanvas/Hud/HandZone") is HandZone,
		"active page contains the persistent HandZone")
	_expect(page.get_node_or_null("GameplayCanvas/Hud/Shop") is Shop,
		"active page contains the persistent Shop")
	_expect(page.get_node_or_null("GameplayCanvas/Hud/ReclaimZone") is ReclaimZone,
		"active page contains the persistent ReclaimZone")
	_expect(page.get_node_or_null("GameplayCanvas/Hud/Board/BoardZone") is BoardZone,
		"Board owns the BoardZone")
	_expect(page.get_node_or_null("GameplayCanvas/Hud/Board/BoardEventZone") is BoardEventZone,
		"Board owns the BoardEventZone")
	_expect(page.find_children("*", "DraggerLayer", true, false).size() == 1,
		"active page has exactly one DraggerLayer")
	await _free_page(page)


func _test_all_card_zones_share_the_same_drag_layer() -> void:
	var page := await _create_page()
	if page == null:
		return
	var drag_layer := page.get_node_or_null("GameplayCanvas/DragLayer") as DraggerLayer
	_expect(drag_layer != null, "shared DraggerLayer exists before zone registration checks")
	if drag_layer != null:
		var registered_zones := drag_layer.get_registered_zones()
		for zone_path in [
			"GameplayCanvas/Hud/HandZone",
			"GameplayCanvas/Hud/Board/BoardZone",
			"GameplayCanvas/Hud/Shop/MarginContainer/VBoxContainer/ShopZone",
			"GameplayCanvas/Hud/ReclaimZone",
		]:
			var zone := page.get_node_or_null(zone_path)
			_expect(zone != null and zone in registered_zones,
				"%s is registered with the shared DraggerLayer" % zone_path)
	await _free_page(page)


func _test_board_return_has_one_page_handler() -> void:
	var page := await _create_page()
	if page == null:
		return
	var board := page.get_node_or_null("GameplayCanvas/Hud/Board") as Board
	_expect(board != null, "Board exists before return-routing checks")
	if board != null:
		var connections := board.card_return_requested.get_connections()
		_expect(connections.size() == 1, "Board return signal has exactly one production handler")
		if connections.size() == 1:
			var callback: Callable = connections[0].callable
			_expect(callback.get_object() == page,
				"GameManager is the only page-level return handler")
			_expect(callback.get_method() == &"_on_board_card_return_requested",
				"Board return signal targets the dedicated GameManager handler")
	await _free_page(page)


func _test_active_page_excludes_legacy_zone_composition() -> void:
	var page := await _create_page()
	if page == null:
		return
	_expect(page.get_node_or_null("GameplayCanvas/PersistentMarket") == null,
		"active page no longer instantiates PersistentMarket")
	_expect(page.get_node_or_null("GameplayCanvas/CardManager") == null,
		"active page no longer instantiates CardManager")
	_expect(page.get_node_or_null("GameplayCanvas/HandManager") == null,
		"active page no longer instantiates HandArea")
	_expect(page.get_node_or_null("GameplayCanvas/HandTray") == null,
		"active page no longer instantiates the retired hand-frame background")
	_expect(page.find_children("*", "HandArea", true, false).is_empty(),
		"active page tree contains no HandArea")
	var active_hud := page.get_node_or_null("GameplayCanvas/Hud")
	_expect(active_hud != null, "active HUD exists before legacy card checks")
	if active_hud != null:
		_expect(active_hud.find_children("*", "CardEntity", true, false).is_empty(),
			"persistent card zones contain no legacy CardEntity")
	await _free_page(page)


func _create_page() -> Node:
	var page := GAME_MANAGER_SCENE.instantiate()
	_expect(page != null, "GameManager scene instantiates")
	if page == null:
		return null
	_expect(page.configure_run(REVIVAL_DECK), "page fixture accepts a valid starting deck")
	root.add_child(page)
	await process_frame
	return page


func _free_page(page: Node) -> void:
	if page != null and is_instance_valid(page):
		page.queue_free()
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
