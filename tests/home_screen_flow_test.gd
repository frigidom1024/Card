extends SceneTree

const MAIN_MENU_SCENE_PATH := "res://scenes/home/main_menu_screen.tscn"
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
		project_config.get_value("application/config", "name", "") == "STACK//STRIKE",
		"project name is STACK//STRIKE"
	)

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
	var subtitle := menu.get_node_or_null("SafeArea/Layout/LogoBlock/GameSubtitle") as Label
	var action_panel := menu.get_node_or_null(
		"SafeArea/Layout/ActionBlock/ActionPanel"
	) as PanelContainer
	var menu_list := menu.get_node_or_null(
		"SafeArea/Layout/ActionBlock/ActionPanel/MenuList"
	) as VBoxContainer
	var start := menu.get_node_or_null(
		"SafeArea/Layout/ActionBlock/ActionPanel/MenuList/StartGameButton"
	) as Button
	var version := menu.get_node_or_null("SafeArea/Layout/FooterBlock/VersionLabel") as Label
	var top_gradient := menu.get_node_or_null("TopGradientOverlay") as TextureRect
	_expect(logo != null and logo.text == "STACK//STRIKE", "menu exposes the STACK//STRIKE title")
	_expect(subtitle != null and subtitle.text == "BUILD A DECK. BREAK THE BOARD.", "menu exposes the STACK//STRIKE subtitle")
	_expect(
		logo != null and logo.get_theme_color("font_color").is_equal_approx(Color(0.95, 0.69, 0.17, 1)),
		"menu title uses bright antique gold"
	)
	_expect(
		logo != null and logo.get_theme_color("font_outline_color").is_equal_approx(Color(0.16, 0.075, 0.018, 1)),
		"menu title uses near-black brown outline"
	)
	_expect(logo != null and logo.get_theme_constant("outline_size") == 4, "menu title uses a substantial gold-foil outline")
	_expect(
		subtitle != null and subtitle.get_theme_color("font_color").is_equal_approx(Color(0.69, 0.50, 0.20, 1)),
		"menu subtitle uses parchment gold"
	)
	_expect(subtitle != null and subtitle.get_theme_constant("outline_size") == 1, "menu subtitle keeps a fine outline")
	_expect(
		action_panel != null and action_panel.custom_minimum_size == Vector2(430, 150),
		"menu centers its action within the approved translucent action panel"
	)
	_expect(menu_list != null and menu_list.get_child_count() == 1, "action panel contains only the primary menu action")
	_expect(start != null and start.text == "BEGIN PILGRIMAGE", "menu exposes the pilgrimage action in English")
	_expect(menu.get_node_or_null("AtmosphereOverlay") == null, "menu leaves the illustration free of a full-screen dark overlay")
	_expect(
		top_gradient != null and top_gradient.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"menu has a non-interactive top readability gradient"
	)
	_expect(
		start != null and start.get_theme_stylebox("normal") != null
			and start.get_theme_stylebox("hover") != null
			and start.get_theme_stylebox("pressed") != null
			and start.get_theme_stylebox("disabled") != null
			and start.get_theme_stylebox("focus") != null,
		"pilgrimage CTA exposes all interaction-state styles"
	)
	_expect(start != null and start.get_theme_font_size("font_size") == 26, "pilgrimage CTA uses the approved restrained type scale")
	_expect(logo != null and logo.get_theme_font_size("font_size") == 150, "menu preserves the configured title scale")
	_expect(subtitle != null and subtitle.get_theme_font_size("font_size") == 60, "menu preserves the configured subtitle scale")
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
	root.size = Vector2i(1920, 1080)
	root.add_child(screen)
	await process_frame
	await process_frame
	await process_frame

	var option_list := screen.find_child("RootOptionList", true, false)
	var root_preview_slot := screen.find_child("RootPreviewSlot", true, false)
	var starter_preview_row := screen.find_child("RemainingStarterCardPreviewRow", true, false)
	var unlock_hint := screen.find_child("UnlockHintLabel", true, false) as Label
	var start := screen.find_child("StartExplorationButton", true, false) as Button
	var back := screen.find_child("BackButton", true, false) as Button
	var title := screen.find_child("TitleLabel", true, false) as Label
	var section_title := screen.find_child("SectionTitle", true, false) as Label
	var starter_title := screen.find_child("StarterTitle", true, false) as Label
	var content := screen.get_node_or_null("SafeArea/Content") as MarginContainer
	var choice_panel := screen.find_child("ChoicePanel", true, false) as PanelContainer
	var preview_panel := screen.find_child("PreviewPanel", true, false) as PanelContainer
	var background := screen.get_node_or_null("Background") as TextureRect
	var top_gradient := screen.get_node_or_null("TopGradientOverlay") as TextureRect
	_expect(
		background != null and background.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"root selection reuses the non-interactive pilgrimage illustration background"
	)
	_expect(
		top_gradient != null and top_gradient.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"root selection has a non-interactive top readability gradient"
	)
	_expect(screen.get_node_or_null("AtmosphereOverlay") == null, "root selection avoids darkening the full illustration")
	_expect(title != null and title.text == "CHOOSE A ROOT", "root selection uses an English title")
	_expect(section_title != null and section_title.text == "AVAILABLE ROOTS", "root list uses an English section title")
	_expect(starter_title != null and starter_title.text == "REMAINING STARTING CARDS", "starter preview uses an English section title")
	_expect(
		title != null and title.get_theme_color("font_color").is_equal_approx(Color(0.95, 0.69, 0.17, 1)),
		"root selection title uses the home screen antique gold"
	)
	_expect(
		choice_panel != null and choice_panel.get_theme_stylebox("panel") != null
			and preview_panel != null and preview_panel.get_theme_stylebox("panel") != null,
		"root selection uses framed pilgrimage panels for choice and preview"
	)
	_expect(
		content != null and content.size_flags_horizontal == Control.SIZE_EXPAND_FILL,
		"root selection content expands across the available wide-screen space"
	)
	_expect(
		choice_panel != null and preview_panel != null
			and preview_panel.size_flags_stretch_ratio > choice_panel.size_flags_stretch_ratio,
		"root selection allocates additional wide-screen space to the card previews"
	)
	_expect(back != null and back.text == "BACK", "root selection uses an understated English back action")
	_expect(start != null and start.text == "BEGIN EXPEDITION", "root selection uses the English pilgrimage CTA")
	_expect(
		start != null and start.get_theme_stylebox("normal") != null
			and start.get_theme_stylebox("hover") != null
			and start.get_theme_stylebox("pressed") != null
			and start.get_theme_stylebox("disabled") != null
			and start.get_theme_stylebox("focus") != null,
		"root selection CTA exposes every interaction state"
	)
	_expect(option_list != null and option_list.get_child_count() == 2, "valid unlocked and locked presets are visible; invalid and duplicate entries are suppressed")
	if option_list != null and option_list.get_child_count() > 0:
		var selected_option := option_list.get_child(0) as RootOptionEntry
		var selected_option_button := selected_option.get_node_or_null("Button") as Button if selected_option != null else null
		var selected_option_name := selected_option.find_child("NameLabel", true, false) as Label if selected_option != null else null
		var selected_option_tag_badge := selected_option.find_child("TagBadge", true, false) as PanelContainer if selected_option != null else null
		var selected_option_tag_label := selected_option.find_child("TagLabel", true, false) as Label if selected_option != null else null
		_expect(
			selected_option_name != null and selected_option_name.text == "RIBWOOD ROOT",
			"root option renders its name separately from playstyle tags"
		)
		_expect(
			selected_option_tag_badge != null and selected_option_tag_badge.get_theme_stylebox("panel") != null
				and selected_option_tag_label != null
				and selected_option_tag_label.text == "HEALING · ENDURANCE · WEAPON CHAIN"
				and selected_option_tag_label.get_theme_font_size("font_size") == 12,
			"root option renders compact playstyle tags in a muted badge"
		)
		_expect(
			selected_option_button != null and selected_option_button.get_theme_stylebox("normal") != null
				and selected_option_button.get_theme_stylebox("hover") != null
				and selected_option_button.get_theme_stylebox("pressed") != null,
			"root option uses the gilt interaction treatment"
		)
	_expect(screen.get("selected_preset") == RevivalDeck, "first valid unlocked preset is selected")
	_expect(root_preview_slot != null and root_preview_slot.get_child_count() == 1, "selected root has one real card preview")
	if root_preview_slot != null and root_preview_slot.get_child_count() == 1:
		_expect(root_preview_slot.get_child(0).call("is_display_only"), "root preview uses display-only CardEntity")
	_expect(
		starter_preview_row != null and starter_preview_row.get_child_count() == RevivalDeck.get_remaining_starter_cards().size(),
		"remaining complete starting deck is previewed without the root"
	)
	if starter_preview_row != null and starter_preview_row.get_child_count() == RevivalDeck.get_remaining_starter_cards().size():
		var first_starter_preview := starter_preview_row.get_child(0) as Node2D
		var last_starter_preview := starter_preview_row.get_child(starter_preview_row.get_child_count() - 1) as Node2D
		_expect(
			first_starter_preview != null and last_starter_preview != null
				and is_equal_approx(
					(first_starter_preview.position.x + last_starter_preview.position.x) * 0.5,
					starter_preview_row.size.x * 0.5
				),
			"remaining starter card previews stay centered after the layout settles"
		)

	var locked_entry = screen.call("_entry_for_preset", locked_deck)
	screen.call("_on_root_option_pressed", locked_entry)
	_expect(screen.get("selected_preset") == RevivalDeck, "locked option cannot replace valid selection")
	_expect(unlock_hint != null and unlock_hint.text.begins_with("THIS ROOT"), "locked option shows an English unlock hint")

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
	_expect(main.get_node_or_null("ScreenLayer/MainMenuScreen") == null, "debug boot skips the main menu")
	main.free()
	await process_frame

func _test_main_routes_menu_selection_and_fresh_runs() -> void:
	var main := MainScene.instantiate()
	main.debug_start_into_game = false
	root.add_child(main)
	await process_frame

	var menu := main.get_node_or_null("ScreenLayer/MainMenuScreen") as Control
	_expect(menu != null, "boot shows main menu")
	_expect(main.get_node_or_null("GameManager") == null, "boot does not create a game manager")
	if menu != null:
		var first_start := menu.get_node_or_null("SafeArea/Layout/ActionBlock/ActionPanel/MenuList/StartGameButton") as Button
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
		var second_start := menu.get_node_or_null("SafeArea/Layout/ActionBlock/ActionPanel/MenuList/StartGameButton") as Button
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
