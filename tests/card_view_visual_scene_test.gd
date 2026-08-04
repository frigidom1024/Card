extends SceneTree

const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const CardViewScene = preload("res://scenes/card_view/card_view.tscn")
const ThornHeavyBlade = preload("res://data/cards/ThornHeavyBlade.tres")
const CARD_ARTWORK_PATH := "res://assert/card/ribwood_guardian_root.png"
const CARD_ARTWORK_UID := "uid://0lvd6foamt4r"

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
	await _test_card_view_head_indicator_points_outward_and_rotates_with_card()
	await _test_scene_preview_artwork_overlays_placeholder()
	await _test_card_view_shows_placeholder_without_artwork()
	await _test_card_view_loads_artwork_from_data_path()
	await _test_card_entity_loads_artwork_from_uid_path()
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
			var paper_core_style := paper_core.get_theme_stylebox("panel") as StyleBoxFlat
			_expect(paper_core_style != null and paper_core_style.bg_color.a <= 0.18, "%s keeps its paper core transparent enough for artwork" % scene_path)
		frame.free()


func _test_card_view_has_visual_hosts() -> void:
	var view := CardViewScene.instantiate() as Control
	root.add_child(view)
	await process_frame

	_expect(view.get_node_or_null("FrameHost") != null, "card view exposes a frame host")
	_expect(view.get_node_or_null("NamePlate") == null, "card view does not render a removed title plate")

	view.free()
	await process_frame


func _test_card_view_head_indicator_points_outward_and_rotates_with_card() -> void:
	var view := CardViewScene.instantiate() as Control
	root.add_child(view)
	await process_frame

	var indicator := view.get_node_or_null("HeadIndicator") as Control
	var glow := view.get_node_or_null("HeadIndicator/ArrowGlow") as Polygon2D
	var body := view.get_node_or_null("HeadIndicator/ArrowBody") as Polygon2D
	_expect(indicator != null, "card view exposes a head direction indicator")
	_expect(indicator != null and not indicator.visible, "head direction indicator is hidden by default")
	_expect(indicator != null and indicator.mouse_filter == Control.MOUSE_FILTER_IGNORE, "head direction indicator does not intercept pointer input")
	_expect(glow != null and glow.polygon.size() >= 5, "head indicator exposes a geometric glow arrow")
	_expect(body != null and body.polygon.size() >= 5, "head indicator exposes a geometric body arrow")

	view.set_head_indicator_visible(true)
	await process_frame
	_expect(indicator != null and indicator.visible, "head direction indicator can be enabled explicitly")

	if indicator != null:
		_expect(indicator.position.x > 0.0 and indicator.position.x + indicator.size.x < view.size.x, "head indicator is horizontally centered within the card")
		_expect(indicator.position.y + indicator.size.y < 0.0, "head indicator is outside the card's top edge")

	var rotation_before: float = 0.0
	if indicator != null:
		rotation_before = indicator.get_global_transform_with_canvas().get_rotation()
	view.rotation = PI / 2.0
	await process_frame
	if indicator != null:
		var indicator_rotation := indicator.get_global_transform_with_canvas().get_rotation()
		var view_rotation := view.get_global_transform_with_canvas().get_rotation()
		_expect(is_equal_approx(indicator_rotation, view_rotation), "head indicator rotates with the card view")
		_expect(not is_equal_approx(rotation_before, indicator_rotation), "head indicator changes orientation when the card rotates")

	view.free()
	await process_frame


func _test_scene_preview_artwork_overlays_placeholder() -> void:
	var view := CardViewScene.instantiate() as Control
	root.add_child(view)
	await process_frame

	var artwork := view.get_node_or_null("Artwork") as TextureRect
	var placeholder := view.get_node_or_null("ArtworkPlaceholder") as Control
	_expect(artwork != null and placeholder != null and artwork.get_index() > placeholder.get_index(), "scene-preview artwork renders above the placeholder")

	view.free()
	await process_frame


func _test_card_view_shows_placeholder_without_artwork() -> void:
	var view := CardViewScene.instantiate() as Control
	root.add_child(view)
	await process_frame

	var artwork := view.get_node_or_null("Artwork") as TextureRect
	var placeholder := view.get_node_or_null("ArtworkPlaceholder") as Control
	_expect(artwork != null, "card view exposes an artwork texture layer")
	_expect(placeholder != null, "card view exposes a no-art placeholder")
	if artwork != null:
		_expect(not artwork.visible, "card view hides artwork when no image path exists")
		_expect(artwork.texture == null, "card view clears artwork without an image path")
	if placeholder != null:
		_expect(placeholder.visible, "card view shows placeholder when no image path exists")

	view.free()
	await process_frame


func _test_card_view_loads_artwork_from_data_path() -> void:
	var data := CardData.new()
	var supports_artwork_path := _has_property(data, "artwork_path")
	_expect(supports_artwork_path, "card data exposes an artwork path")
	if not supports_artwork_path:
		return

	data.set("artwork_path", CARD_ARTWORK_PATH)
	var view := CardViewScene.instantiate() as Control
	root.add_child(view)
	await process_frame
	view.set_value(CardInstance.new(data))
	await process_frame

	var artwork := view.get_node_or_null("Artwork") as TextureRect
	var placeholder := view.get_node_or_null("ArtworkPlaceholder") as Control
	var frame_host := view.get_node_or_null("FrameHost") as Control
	_expect(artwork != null and artwork.visible, "card view shows artwork for a valid path")
	_expect(artwork != null and artwork.texture != null, "card view loads the configured artwork texture")
	_expect(placeholder != null and not placeholder.visible, "card view hides placeholder after artwork loads")
	_expect(artwork != null and frame_host != null and artwork.get_index() < frame_host.get_index(), "card frame renders above artwork")

	view.free()
	await process_frame


func _test_card_entity_loads_artwork_from_uid_path() -> void:
	var data := CardData.new()
	data.artwork_path = CARD_ARTWORK_UID
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(CardInstance.new(data))
	root.add_child(card)
	await process_frame
	await process_frame

	var artwork := card.get_node_or_null("CardView/Artwork") as TextureRect
	var placeholder := card.get_node_or_null("CardView/ArtworkPlaceholder") as Control
	_expect(artwork != null and artwork.visible and artwork.texture != null, "card entity renders artwork from an Inspector UID path")
	_expect(placeholder != null and not placeholder.visible, "card entity hides the placeholder after a UID artwork loads")

	card.free()
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


func _has_property(resource: Resource, property_name: String) -> bool:
	for property in resource.get_property_list():
		if property.name == property_name:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)