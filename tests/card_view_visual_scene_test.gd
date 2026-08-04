extends SceneTree

const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const CardViewScene = preload("res://scenes/card_view/card_view.tscn")
const ThornHeavyBlade = preload("res://data/cards/ThornHeavyBlade.tres")

const FRAME_SCENE_PATHS := [
	"res://scenes/card_view/frames/card_frame_common.tscn",
	"res://scenes/card_view/frames/card_frame_rare.tscn",
	"res://scenes/card_view/frames/card_frame_epic.tscn",
	"res://scenes/card_view/frames/card_frame_legendary.tscn",
]

const STAT_TAG_SCENE_PATHS := [
	"res://scenes/card_view/stat_tags/card_stat_tag_damage.tscn",
	"res://scenes/card_view/stat_tags/card_stat_tag_guard.tscn",
	"res://scenes/card_view/stat_tags/card_stat_tag_heal.tscn",
]

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_editable_visual_scenes_exist()
	_test_rarity_frames_include_subtle_paper_depth()
	await _test_card_view_has_visual_hosts()
	await _test_damage_tag_stays_upright_below_rotated_card()
	quit(1 if _failure_count > 0 else 0)


func _test_editable_visual_scenes_exist() -> void:
	for scene_path in FRAME_SCENE_PATHS:
		_expect(ResourceLoader.exists(scene_path), "%s exists as an editable rarity frame scene" % scene_path)

	for scene_path in STAT_TAG_SCENE_PATHS:
		_expect(ResourceLoader.exists(scene_path), "%s exists as an editable stat-tag scene" % scene_path)


func _test_rarity_frames_include_subtle_paper_depth() -> void:
	for scene_path in FRAME_SCENE_PATHS:
		var frame := load(scene_path).instantiate() as Control
		var soft_shadow := frame.get_node_or_null("SoftShadow") as Panel
		var paper_core := frame.get_node_or_null("PaperCore") as Panel
		_expect(soft_shadow != null, "%s exposes a soft paper shadow" % scene_path)
		_expect(paper_core != null, "%s exposes a paper core edge" % scene_path)
		if soft_shadow != null:
			_expect(soft_shadow.position == Vector2(1.0, 2.0), "%s keeps its shadow subtle" % scene_path)
		if paper_core != null:
			_expect(paper_core.position == Vector2(1.0, 1.0), "%s keeps its paper edge subtle" % scene_path)
		frame.free()


func _test_card_view_has_visual_hosts() -> void:
	var view := CardViewScene.instantiate() as Control
	root.add_child(view)
	await process_frame

	_expect(view.get_node_or_null("FrameHost") != null, "card view exposes a frame host")
	_expect(view.get_node_or_null("NamePlate") == null, "card view does not render a removed title plate")

	view.free()
	await process_frame


func _test_damage_tag_stays_upright_below_rotated_card() -> void:
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(CardInstance.new(ThornHeavyBlade))
	root.add_child(card)
	await process_frame
	await process_frame

	var tag_anchor := card.get_node_or_null("CombatTagAnchor") as Control
	_expect(tag_anchor != null, "card entity owns a combat-tag anchor")
	if tag_anchor != null:
		_expect(not tag_anchor.z_as_relative, "combat tags use an absolute draw layer")
		_expect(tag_anchor.z_index > 100, "combat tags render above dragged cards")
		var tag_container := tag_anchor.get_node_or_null("TagContainer") as Container
		_expect(tag_container != null, "combat-tag anchor exposes a tag container")
		_expect(tag_container != null and tag_container.get_child_count() == 1, "damage-only card creates one stat tag")
		if tag_container != null and tag_container.get_child_count() == 1:
			var damage_tag := tag_container.get_child(0) as Control
			var attribute_label := damage_tag.get_node_or_null("AttributeLabel") as Label
			var value_label := damage_tag.get_node_or_null("ValueLabel") as Label
			_expect(attribute_label == null, "damage tag does not include an attribute text prefix")
			_expect(value_label != null and value_label.text == "4", "damage tag shows only the card damage value")

		card.rotation = PI / 2.0
		await process_frame
		var card_rect := LayoutConfig.card_view_rect(LayoutConfig.CELL_SIZE)
		var global_right_top := card.to_global(card_rect.position + Vector2(card_rect.size.x, 0.0))
		var global_right_bottom := card.to_global(card_rect.position + card_rect.size)
		var expected_global_bottom_center := (global_right_top + global_right_bottom) * 0.5 + Vector2(0.0, 2.0)
		var tag_global_center := tag_anchor.global_position + tag_anchor.size * 0.5
		_expect(tag_global_center.distance_to(expected_global_bottom_center) < 0.1, "combat tags attach below the card's global bottom edge after rotation")
		_expect(is_zero_approx(tag_anchor.get_global_transform_with_canvas().get_rotation()), "combat tags stay upright when their card rotates")

	card.free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)