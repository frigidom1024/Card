extends SceneTree

const MAIN_MENU_SCENE_PATH := "res://scenes/home/main_menu_screen.tscn"
const ROOT_SELECTION_SCENE_PATH := "res://scenes/home/root_selection_screen.tscn"
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")
const MainScene = preload("res://scenes/main.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_main_menu_structure_and_single_start_request()
	await _test_root_selection_filters_presets_and_requests_exploration_once()
	await _test_main_routes_menu_selection_and_fresh_runs()
	quit(1 if _failure_count > 0 else 0)


func _test_main_menu_structure_and_single_start_request() -> void:
	var packed_scene := load(MAIN_MENU_SCENE_PATH) as PackedScene
	_expect(packed_scene != null, "main menu scene loads")
	if packed_scene == null:
		return

	var menu := packed_scene.instantiate() as Control
	_expect(menu != null, "main menu scene instantiates as Control")
	if menu == null:
		return

	root.add_child(menu)
	await process_frame

	var logo := menu.get_node_or_null("SafeArea/Layout/LogoBlock/GameLogo") as Label
	var start := menu.get_node_or_null("SafeArea/Layout/ActionBlock/StartGameButton") as Button
	var version := menu.get_node_or_null("SafeArea/Layout/FooterBlock/VersionLabel") as Label
	_expect(logo != null and logo.text == "MONOCARD", "menu exposes top logo")
	_expect(start != null and start.text == "开始游戏", "menu exposes the only action")
	_expect(version != null and not version.text.is_empty(), "menu exposes version footer")

	var calls := {"count": 0}
	_expect(menu.has_signal("start_game_requested"), "main menu exposes start_game_requested signal")
	if menu.has_signal("start_game_requested"):
		menu.connect("start_game_requested", func() -> void: calls["count"] += 1)
	if start != null:
		start.emit_signal("pressed")
		start.emit_signal("pressed")
	_expect(calls["count"] == 1 and start.disabled, "start request is emitted once and disables button")

	menu.queue_free()
	await process_frame


func _test_root_selection_filters_presets_and_requests_exploration_once() -> void:
	var packed_scene := load(ROOT_SELECTION_SCENE_PATH) as PackedScene
	_expect(packed_scene != null, "root selection scene loads")
	if packed_scene == null:
		return

	var locked_deck := RevivalDeck.duplicate(true) as StartingDeckData
	locked_deck.deck_id = "locked-revival"
	locked_deck.display_name = "封存的复苏之根"
	locked_deck.is_unlocked = false

	var duplicate_root_deck := RevivalDeck.duplicate(true) as StartingDeckData
	duplicate_root_deck.deck_id = "duplicate-revival"
	duplicate_root_deck.display_name = "重复的复苏之根"

	var invalid_deck := StartingDeckData.new()
	invalid_deck.deck_id = "invalid"
	invalid_deck.display_name = "无效牌组"

	var screen := packed_scene.instantiate() as Control
	_expect(screen != null, "root selection scene instantiates as Control")
	if screen == null:
		return

	var presets: Array[StartingDeckData] = []
	presets.append(RevivalDeck)
	presets.append(locked_deck)
	presets.append(duplicate_root_deck)
	presets.append(invalid_deck)
	screen.call("configure", presets)
	root.add_child(screen)
	await process_frame

	var option_list := screen.find_child("RootOptionList", true, false)
	var root_preview_slot := screen.find_child("RootPreviewSlot", true, false)
	var starter_preview_row := screen.find_child("RemainingStarterCardPreviewRow", true, false)
	var unlock_hint := screen.find_child("UnlockHintLabel", true, false) as Label
	var start := screen.find_child("StartExplorationButton", true, false) as Button
	_expect(option_list != null and option_list.get_child_count() == 2, "valid unlocked and locked presets are visible; invalid and duplicate entries are suppressed")
	if option_list != null and option_list.get_child_count() > 0:
		var selected_option_button := option_list.get_child(0).get_node_or_null("Button") as Button
		_expect(
			selected_option_button != null and selected_option_button.text.contains("复苏之根"),
			"root option renders the selected preset name"
		)
	_expect(screen.get("selected_preset") == RevivalDeck, "first valid unlocked preset is selected")
	_expect(root_preview_slot != null and root_preview_slot.get_child_count() == 1, "selected root has one real card preview")
	if root_preview_slot != null and root_preview_slot.get_child_count() == 1:
		_expect(root_preview_slot.get_child(0).call("is_display_only"), "root preview uses display-only CardEntity")
	_expect(starter_preview_row != null and starter_preview_row.get_child_count() == 4, "remaining complete starting deck is previewed without the root")

	var locked_entry = screen.call("_entry_for_preset", locked_deck)
	screen.call("_on_root_option_pressed", locked_entry)
	_expect(screen.get("selected_preset") == RevivalDeck, "locked option cannot replace valid selection")
	_expect(unlock_hint != null and not unlock_hint.text.is_empty(), "locked option shows an unlock hint")

	var requests := {"count": 0, "preset": null}
	_expect(screen.has_signal("exploration_requested"), "root selection exposes exploration_requested signal")
	if screen.has_signal("exploration_requested"):
		screen.connect("exploration_requested", func(preset: StartingDeckData) -> void:
			requests["count"] += 1
			requests["preset"] = preset
		)
	if start != null:
		start.emit_signal("pressed")
		start.emit_signal("pressed")
	_expect(
		requests["count"] == 1 and requests["preset"] == RevivalDeck and start.disabled,
		"exploration request is emitted once for the selected unlocked preset"
	)

	var main_area := screen.find_child("MainArea", true, false) as BoxContainer
	screen.call("_apply_responsive_layout", Vector2(1920, 1080))
	_expect(main_area != null and not main_area.vertical, "wide root selection layout keeps its columns side by side")
	screen.call("_apply_responsive_layout", Vector2(900, 1200))
	_expect(main_area != null and main_area.vertical, "narrow root selection layout stacks its columns vertically")

	var back_requests := {"count": 0}
	_expect(screen.has_signal("back_requested"), "root selection exposes back_requested signal")
	if screen.has_signal("back_requested"):
		screen.connect("back_requested", func() -> void: back_requests["count"] += 1)
	var back := screen.find_child("BackButton", true, false) as Button
	if back != null:
		back.emit_signal("pressed")
	_expect(back_requests["count"] == 1, "back button delegates navigation through a signal")

	screen.queue_free()
	await process_frame


func _test_main_routes_menu_selection_and_fresh_runs() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame

	var menu := main.get_node_or_null("ScreenLayer/MainMenuScreen") as Control
	_expect(menu != null, "boot shows main menu")
	_expect(main.get_node_or_null("GameManager") == null, "boot does not create a game manager")
	if menu != null:
		var first_start := menu.get_node_or_null("SafeArea/Layout/ActionBlock/StartGameButton") as Button
		if first_start != null:
			first_start.emit_signal("pressed")
	await process_frame

	var selector := main.get_node_or_null("ScreenLayer/RootSelectionScreen") as Control
	_expect(selector != null, "start opens root selection")
	_expect(main.get_node_or_null("GameManager") == null, "root selection does not create a game manager")
	if selector != null:
		var back := selector.find_child("BackButton", true, false) as Button
		if back != null:
			back.emit_signal("pressed")
	await process_frame

	menu = main.get_node_or_null("ScreenLayer/MainMenuScreen") as Control
	_expect(menu != null, "returning from root selection restores the main menu")
	_expect(main.get_node_or_null("GameManager") == null, "returning from root selection still has no game manager")
	if menu != null:
		var second_start := menu.get_node_or_null("SafeArea/Layout/ActionBlock/StartGameButton") as Button
		if second_start != null:
			second_start.emit_signal("pressed")
	await process_frame

	selector = main.get_node_or_null("ScreenLayer/RootSelectionScreen") as Control
	_expect(selector != null, "main menu can open root selection again after returning")
	if selector != null:
		var start_exploration := selector.find_child("StartExplorationButton", true, false) as Button
		if start_exploration != null:
			start_exploration.emit_signal("pressed")
	await process_frame

	var run_one := main.get_node_or_null("GameManager")
	_expect(run_one != null and run_one.starting_deck == RevivalDeck, "exploration injects the selected starting deck")
	_expect(main.get_node_or_null("ScreenLayer/RootSelectionScreen") == null, "root selection is destroyed when exploration starts")
	var first_card: Variant = run_one.cards_inst[0] if run_one != null and not run_one.cards_inst.is_empty() else null

	if run_one != null:
		run_one.queue_free()
	await process_frame
	main.call("_show_root_selection")
	await process_frame
	selector = main.get_node_or_null("ScreenLayer/RootSelectionScreen") as Control
	if selector != null:
		var second_exploration_start := selector.find_child("StartExplorationButton", true, false) as Button
		if second_exploration_start != null:
			second_exploration_start.emit_signal("pressed")
	await process_frame

	var run_two := main.get_node_or_null("GameManager")
	_expect(run_two != null and run_two.cards_inst[0] != first_card, "starting the same deck creates fresh card instances")

	main.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
