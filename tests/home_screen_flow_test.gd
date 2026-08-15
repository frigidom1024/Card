extends SceneTree

const MAIN_MENU_SCENE_PATH := "res://scenes/menu.tscn"
const ROOT_SELECTION_SCENE_PATH := "res://scenes/home/root_selection_screen.tscn"
const PROJECT_CONFIG_PATH := "res://project.godot"
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")
const MainScene = preload("res://scenes/main.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_main_menu_structure_and_single_start_request()
	await _test_root_selection_filters_presets_and_requests_exploration_once()
	await _test_debug_build_starts_configured_deck_directly()
	await _test_main_routes_menu_selection_and_fresh_runs()
	quit(1 if _failure_count > 0 else 0)


func _test_main_menu_structure_and_single_start_request() -> void:
	var project_config := ConfigFile.new()
	_expect(project_config.load(PROJECT_CONFIG_PATH) == OK, "project config loads")
	_expect(
		project_config.get_value("application", "config/name", "") == "STACK//STRIKE",
		"project name is STACK//STRIKE"
	)

	var packed_scene := load(MAIN_MENU_SCENE_PATH) as PackedScene
	_expect(packed_scene != null, "new menu scene loads")
	if packed_scene == null:
		return

	var menu := packed_scene.instantiate() as Control
	_expect(menu != null, "new menu scene instantiates as Control")
	if menu == null:
		return

	root.add_child(menu)
	await process_frame

	var title := menu.get_node_or_null("MarginContainer/Panel/Title2") as RichTextLabel
	var subtitle := menu.get_node_or_null("MarginContainer/Panel/Title3") as RichTextLabel
	var start := menu.get_node_or_null("MarginContainer/Panel/BtnStart") as Button
	_expect(title != null and "STACK" in title.text and "STRIKE" in title.text, "menu exposes STACK//STRIKE branding")
	_expect(subtitle != null and "BUILD A" in subtitle.text and "BREAK THE" in subtitle.text, "menu exposes menu tagline")
	_expect(start != null and start.text == "START", "menu exposes start button")
	_expect(
		start != null and start.get_theme_stylebox("normal") != null
			and start.get_theme_stylebox("hover") != null
			and start.get_theme_stylebox("pressed") != null,
		"start button exposes normal, hover, and pressed styles"
	)

	var calls := {"count": 0}
	_expect(menu.has_signal("start_game_requested"), "menu exposes start_game_requested signal")
	if menu.has_signal("start_game_requested"):
		menu.connect("start_game_requested", func() -> void: calls["count"] += 1)
	if start != null:
		start.emit_signal("pressed")
		start.emit_signal("pressed")
	_expect(calls["count"] == 1 and start != null and start.disabled, "start request is emitted once and disables the button")

	menu.queue_free()
	await process_frame


func _test_root_selection_filters_presets_and_requests_exploration_once() -> void:
	var packed_scene := load(ROOT_SELECTION_SCENE_PATH) as PackedScene
	_expect(packed_scene != null, "root selection scene loads")
	if packed_scene == null:
		return

	var locked_deck := RevivalDeck.duplicate(true) as StartingDeckData
	locked_deck.deck_id = "locked-revival"
	locked_deck.display_name = "SEALED RIBWOOD ROOT"
	locked_deck.is_unlocked = false
	var locked_root := RevivalDeck.get_root_card().duplicate(true) as CardData
	locked_root.card_id = 987654
	locked_root.card_name = "SEALED ROOT"
	var locked_cards: Array[CardData] = [locked_root]
	locked_cards.append_array(RevivalDeck.get_remaining_starter_cards())
	locked_deck.starter_cards = locked_cards

	var duplicate_root_deck := RevivalDeck.duplicate(true) as StartingDeckData
	duplicate_root_deck.deck_id = "duplicate-revival"
	duplicate_root_deck.display_name = "DUPLICATE RIBWOOD ROOT"

	var invalid_deck := StartingDeckData.new()
	invalid_deck.deck_id = "invalid"
	invalid_deck.display_name = "INVALID DECK"

	var screen := packed_scene.instantiate() as RootSelectionScreen
	_expect(screen != null, "root selection scene instantiates as RootSelectionScreen")
	if screen == null:
		return

	var presets: Array[StartingDeckData] = [RevivalDeck, locked_deck, duplicate_root_deck, invalid_deck]
	screen.configure(presets)
	root.size = Vector2i(1920, 1080)
	root.add_child(screen)
	await process_frame
	await process_frame
	await process_frame

	var root_preview_slot := screen.find_child("RootPreviewSlot", true, false) as Control
	var starter_preview_row := screen.find_child("RemainingStarterCardPreviewRow", true, false) as Control
	var unlock_hint := screen.find_child("UnlockHintLabel", true, false) as Label
	var start := screen.find_child("StartExplorationButton", true, false) as Button
	var back := screen.find_child("BackButton", true, false) as Button
	var previous := screen.find_child("PreviousDeckButton", true, false) as Button
	var next := screen.find_child("NextDeckButton", true, false) as Button
	var title := screen.find_child("TitleLabel", true, false) as Label
	var subtitle := screen.find_child("SubtitleLabel", true, false) as RichTextLabel
	var deck_name := screen.find_child("DeckNameLabel", true, false) as Label
	var selection_frame := screen.find_child("SelectionFrame", true, false) as PanelContainer
	var carousel := screen.find_child("DeckCarousel", true, false) as HBoxContainer

	_expect(title != null and title.text == "CHOOSE YOUR DECK", "root selection uses the reference heading")
	_expect(
		subtitle != null and "PICK A" in subtitle.text and "MAKE YOUR" in subtitle.text,
		"root selection uses the reference deck-selection tagline",
	)
	_expect(
		selection_frame != null and selection_frame.get_theme_stylebox("panel") != null,
		"root selection places the carousel in a framed pixel panel",
	)
	_expect(carousel != null, "root selection exposes a horizontal deck carousel")
	_expect(back != null and back.text == "BACK", "root selection keeps the back action")
	_expect(start != null and start.text == "START", "root selection uses the reference START action")
	_expect(
		previous != null and next != null
			and previous.text == "<" and next.text == ">"
			and previous.get_theme_color("font_color").r > 0.7
			and next.get_theme_color("font_color").r > 0.7,
		"deck carousel exposes red previous and next buttons",
	)
	_expect(
		previous != null and next != null and not previous.disabled and not next.disabled,
		"carousel arrows are enabled when two valid decks remain after filtering",
	)
	_expect(screen.selected_preset == RevivalDeck, "first valid unlocked deck is initially selected")
	_expect(deck_name != null and deck_name.text == RevivalDeck.display_name, "selected deck name is shown above the root card")
	_expect(root_preview_slot != null and root_preview_slot.get_child_count() == 1, "central slot owns one root card")
	if root_preview_slot != null and root_preview_slot.get_child_count() == 1:
		var root_card := root_preview_slot.get_child(0) as Card
		_expect(
			root_card != null and root_card.get_card_inst().card_data == RevivalDeck.get_root_card(),
			"central preview is the selected deck root using the new Card model",
		)
		_expect(
			is_equal_approx(root_card.position.x + root_card.size.x * 0.5, root_preview_slot.size.x * 0.5),
			"central root card remains horizontally centered after layout",
		)
	_expect(
		starter_preview_row != null
			and starter_preview_row.get_child_count() == RevivalDeck.get_remaining_starter_cards().size(),
		"bottom row previews all other cards from the selected deck",
	)

	if starter_preview_row != null and starter_preview_row.get_child_count() > 1:
		var first_preview := starter_preview_row.get_child(0) as Card
		var last_preview := starter_preview_row.get_child(starter_preview_row.get_child_count() - 1) as Card
		_expect(
			first_preview != null and last_preview != null
				and absf(
					(first_preview.position.x + first_preview.size.x * 0.5
						+ last_preview.position.x + last_preview.size.x * 0.5) * 0.5
						- starter_preview_row.size.x * 0.5
				) <= 8.0,
			"bottom deck cards remain centered as a group after scattered layout",
		)

	if next != null:
		next.emit_signal("pressed")
	await process_frame
	await process_frame
	_expect(screen.selected_preset == locked_deck, "next arrow selects the next deck")
	_expect(deck_name != null and deck_name.text == locked_deck.display_name, "carousel refreshes the selected deck name")
	_expect(start != null and start.disabled, "locked decks cannot start exploration")
	_expect(unlock_hint != null and unlock_hint.text.begins_with("THIS DECK"), "locked carousel entries show an unlock hint")
	if root_preview_slot != null and root_preview_slot.get_child_count() == 1:
		var locked_preview := root_preview_slot.get_child(0) as Card
		_expect(
			locked_preview != null and locked_preview.get_card_inst().card_data == locked_root,
			"changing decks replaces the central root card",
		)

	if next != null:
		next.emit_signal("pressed")
	await process_frame
	await process_frame
	_expect(screen.selected_preset == RevivalDeck, "next arrow wraps from the last deck to the first")
	_expect(start != null and not start.disabled, "returning to an unlocked deck enables START")

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
		"START emits one exploration request for the selected unlocked deck",
	)

	var back_requests := {"count": 0}
	_expect(screen.has_signal("back_requested"), "root selection exposes back_requested signal")
	if screen.has_signal("back_requested"):
		screen.connect("back_requested", func() -> void: back_requests["count"] += 1)
	if back != null:
		back.emit_signal("pressed")
	_expect(back_requests["count"] == 1, "back button delegates navigation through a signal")

	screen.queue_free()
	await process_frame


func _test_debug_build_starts_configured_deck_directly() -> void:
	if not OS.is_debug_build():
		return

	var main := MainScene.instantiate()
	main.debug_start_into_game = true
	root.add_child(main)
	await process_frame

	var game := main.get_node_or_null("GameManager")
	_expect(game != null, "debug boot creates a game manager directly")
	_expect(
		game != null and game.starting_deck == RevivalDeck,
		"debug boot uses the configured Revival starting deck"
	)
	_expect(main.get_node_or_null("ScreenLayer/Menu") == null, "debug boot skips the main menu")
	main.free()
	await process_frame

func _test_main_routes_menu_selection_and_fresh_runs() -> void:
	var main := MainScene.instantiate()
	main.debug_start_into_game = false
	root.add_child(main)
	await process_frame

	var menu := main.get_node_or_null("ScreenLayer/Menu") as Control
	_expect(menu != null, "boot shows main menu")
	_expect(main.get_node_or_null("GameManager") == null, "boot does not create a game manager")
	if menu != null:
		var first_start := menu.get_node_or_null("MarginContainer/Panel/BtnStart") as Button
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

	menu = main.get_node_or_null("ScreenLayer/Menu") as Control
	_expect(menu != null, "returning from root selection restores the main menu")
	_expect(main.get_node_or_null("GameManager") == null, "returning from root selection still has no game manager")
	if menu != null:
		var second_start := menu.get_node_or_null("MarginContainer/Panel/BtnStart") as Button
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
