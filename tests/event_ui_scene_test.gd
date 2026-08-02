extends SceneTree

const CARD_VIEW_SCENE_PATH := "res://scenes/card_view/card_view.tscn"
const CARD_VIEW_SCRIPT_PATH := "res://scripts/card/card_view.gd"
const SHOP_SCENE_PATH := "res://scenes/game/event_shop.tscn"
const TREASURE_SCENE_PATH := "res://scenes/game/event_treasure.tscn"
const COMBAT_SCENE_PATH := "res://scenes/game/event_combat.tscn"
const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

const COMBAT_NODE_NAMES := [
	"Overlay",
	"Panel",
	"TitleLabel",
	"ProgressLabel",
	"PlayerStatsLabel",
	"MonsterStatsLabel",
	"CombatLog",
	"ProgressButton",
	"ResultPanel",
	"ResultTitleLabel",
	"ResultBodyLabel",
	"PenaltyList",
	"ConfirmButton",
]

const COMMON_NODE_NAMES := [
	"Overlay",
	"Panel",
	"Header",
	"TitleLabel",
	"SubtitleLabel",
	"CloseButton",
	"OfferContainer",
	"OfferSlot1",
	"OfferSlot2",
	"OfferSlot3",
	"HintLabel",
]

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_shop_scene_structure()
	_test_treasure_scene_structure()
	_test_combat_scene_structure()
	await _test_event_views_are_not_children_of_gameplay_canvas()
	await _assert_runtime_modal_layout(SHOP_SCENE_PATH, "shop")
	await _assert_runtime_modal_layout(TREASURE_SCENE_PATH, "treasure")
	await _assert_runtime_modal_layout(COMBAT_SCENE_PATH, "combat")
	_finish_tests()


func _test_shop_scene_structure() -> void:
	var scene_root := _instantiate_scene(SHOP_SCENE_PATH)
	if scene_root == null:
		return

	_expect(scene_root.name == "EventShop", "shop root is named EventShop")
	_expect(scene_root.anchors_preset == Control.PRESET_FULL_RECT, "shop root covers the viewport")
	_expect(scene_root.find_child("GoldLabel", true, false) != null, "shop exposes GoldLabel")
	_expect(_find_all(scene_root, "CardPreview").size() == 3, "shop exposes three card previews")
	_assert_common_structure(scene_root, "shop")
	_assert_card_preview_instances(scene_root, "shop")
	scene_root.free()


func _test_treasure_scene_structure() -> void:
	var scene_root := _instantiate_scene(TREASURE_SCENE_PATH)
	if scene_root == null:
		return

	_expect(scene_root.name == "EventTreasure", "treasure root is named EventTreasure")
	_expect(scene_root.anchors_preset == Control.PRESET_FULL_RECT, "treasure root covers the viewport")
	_expect(_find_all(scene_root, "CardPreview").size() == 2, "treasure exposes two card previews")
	_expect(
		scene_root.find_child("GoldRewardPreview", true, false) != null,
		"treasure exposes a dedicated GoldRewardPreview"
	)
	_assert_common_structure(scene_root, "treasure")
	_assert_card_preview_instances(scene_root, "treasure")
	scene_root.free()


func _test_combat_scene_structure() -> void:
	var scene_root := _instantiate_scene(COMBAT_SCENE_PATH)
	if scene_root == null:
		return

	_expect(scene_root.name == "EventCombat", "combat root is named EventCombat")
	_expect(scene_root.anchors_preset == Control.PRESET_FULL_RECT, "combat root covers the viewport")
	for node_name in COMBAT_NODE_NAMES:
		_expect(
			scene_root.find_child(node_name, true, false) != null,
			"combat exposes stable node %s" % node_name
		)
	scene_root.free()

func _test_event_views_are_not_children_of_gameplay_canvas() -> void:
	var manager := GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "event UI setup configures a starting deck")
	root.add_child(manager)
	await process_frame

	var gameplay_canvas := manager.get_node_or_null("GameplayCanvas")
	var event_layer := manager.get_node_or_null("EventModalLayer") as CanvasLayer
	_expect(gameplay_canvas != null, "game manager has gameplay canvas")
	_expect(event_layer != null, "game manager has event modal canvas layer")
	for view_name in ["ShopEventView", "TreasureEventView", "CombatEventView"]:
		var view := event_layer.get_node_or_null(view_name) as Control if event_layer != null else null
		_expect(view != null, "%s remains under event modal layer" % view_name)
		if view != null:
			_expect(event_layer.is_ancestor_of(view), "%s inherits the event modal layer" % view_name)
			if gameplay_canvas != null:
				_expect(not gameplay_canvas.is_ancestor_of(view), "%s is not scaled with gameplay" % view_name)
			_expect(view.anchors_preset == Control.PRESET_FULL_RECT, "%s covers the actual viewport" % view_name)

	manager.queue_free()
	await process_frame


func _instantiate_scene(scene_path: String) -> Control:
	var packed_scene := load(scene_path) as PackedScene
	_expect(packed_scene != null, "%s loads as a PackedScene" % scene_path)
	if packed_scene == null:
		return null

	var scene_root := packed_scene.instantiate() as Control
	_expect(scene_root != null, "%s instantiates as a Control" % scene_path)
	return scene_root


func _assert_runtime_modal_layout(scene_path: String, scene_name: String) -> void:
	var scene_root := _instantiate_scene(scene_path)
	if scene_root == null:
		return

	root.add_child(scene_root)
	await process_frame
	await process_frame

	var viewport_size := root.get_visible_rect().size
	var overlay := scene_root.find_child("Overlay", true, false) as Control
	var panel := scene_root.find_child("Panel", true, false) as Control
	_expect(overlay != null and overlay.size == viewport_size, "%s overlay covers the viewport at runtime" % scene_name)
	_expect(panel != null and panel.size.x >= 960.0 and panel.size.y >= 610.0, "%s panel keeps its modal minimum size" % scene_name)
	if panel != null:
		var panel_center := panel.global_position + panel.size / 2.0
		_expect(
			panel_center.distance_to(viewport_size / 2.0) <= 1.0,
			"%s panel is centered at runtime" % scene_name
		)

	scene_root.queue_free()
	await process_frame


func _assert_common_structure(scene_root: Control, scene_name: String) -> void:
	for node_name in COMMON_NODE_NAMES:
		_expect(
			scene_root.find_child(node_name, true, false) != null,
			"%s exposes stable node %s" % [scene_name, node_name]
		)

	for offer_index in range(1, 4):
		var slot := scene_root.find_child("OfferSlot%d" % offer_index, true, false)
		_expect(slot != null, "%s exposes OfferSlot%d" % [scene_name, offer_index])
		if slot == null:
			continue
		_expect(
			slot.find_child("PriceOrRewardLabel", true, false) != null,
			"%s OfferSlot%d exposes PriceOrRewardLabel" % [scene_name, offer_index]
		)
		_expect(
			slot.find_child("ActionButton", true, false) != null,
			"%s OfferSlot%d exposes ActionButton" % [scene_name, offer_index]
		)


func _assert_card_preview_instances(scene_root: Control, scene_name: String) -> void:
	for card_preview in _find_all(scene_root, "CardPreview"):
		_expect(
			card_preview.scene_file_path == CARD_VIEW_SCENE_PATH,
			"%s CardPreview directly instances card_view.tscn" % scene_name
		)
		var card_view_script := card_preview.get_script() as Script
		_expect(
			card_view_script != null and card_view_script.resource_path == CARD_VIEW_SCRIPT_PATH,
			"%s CardPreview uses the existing CardView renderer" % scene_name
		)


func _find_all(scene_root: Node, node_name: String) -> Array[Node]:
	var matches: Array[Node] = []
	for node in scene_root.find_children(node_name, "", true, false):
		matches.append(node)
	return matches


func _finish_tests() -> void:
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
