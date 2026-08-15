extends SceneTree

const EventHoverPreviewScene = preload("res://scenes/game/event_hover_preview.tscn")
const EventHoverPreviewModelScript = preload(
	"res://scripts/game/event/hover/event_hover_preview_model.gd"
)
const CardInfoPanel = preload("res://assert/ui/card_info_panel.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_preview_scene_uses_card_hover_visual_language()
	await _test_preview_scene_displays_and_dismisses_model()
	quit(1 if _failure_count > 0 else 0)


func _test_preview_scene_uses_card_hover_visual_language() -> void:
	var preview := EventHoverPreviewScene.instantiate() as PanelContainer
	root.add_child(preview)
	await process_frame

	var badge_row := preview.get_node_or_null("MarginContainer/Content/BadgeRow") as HBoxContainer
	var type_badge := preview.get_node_or_null(
		"MarginContainer/Content/BadgeRow/TypeBadge"
	) as PanelContainer
	var type_label := preview.get_node_or_null(
		"MarginContainer/Content/BadgeRow/TypeBadge/TypeLabel"
	) as Label
	var category_label := preview.get_node_or_null(
		"MarginContainer/Content/BadgeRow/CategoryBadge/CategoryLabel"
	) as Label
	var title_panel := preview.get_node_or_null("MarginContainer/Content/TitlePanel") as PanelContainer
	var title := preview.get_node_or_null("MarginContainer/Content/TitlePanel/TitleLabel") as Label
	var top_divider := preview.get_node_or_null("MarginContainer/Content/TopDivider") as HBoxContainer
	var stats_divider := preview.get_node_or_null(
		"MarginContainer/Content/StatsSection/Divider"
	) as HBoxContainer
	var rewards_divider := preview.get_node_or_null(
		"MarginContainer/Content/RewardsSection/Divider"
	) as HBoxContainer
	var abilities_divider := preview.get_node_or_null(
		"MarginContainer/Content/AbilitiesSection/Divider"
	) as HBoxContainer

	_expect(preview.custom_minimum_size.x >= 430.0, "event preview matches the wide card HoverInfo silhouette")
	_expect(
		preview.get_theme_stylebox("panel") == CardInfoPanel,
		"event preview reuses the card HoverInfo panel frame",
	)
	_expect(badge_row != null and type_badge != null and type_label != null, "event preview has a dynamic type badge")
	_expect(category_label != null and category_label.text == "EVENT", "event preview has the fixed EVENT badge")
	_expect(title_panel != null and title != null, "event preview presents its title on a light title plate")
	_expect(
		top_divider != null and stats_divider != null and rewards_divider != null and abilities_divider != null,
		"event preview uses pixel dividers throughout its content sections",
	)
	_expect(preview.mouse_filter == Control.MOUSE_FILTER_IGNORE, "preview root ignores pointer input")

	preview.queue_free()
	await process_frame


func _test_preview_scene_displays_and_dismisses_model() -> void:
	var preview := EventHoverPreviewScene.instantiate() as EventHoverPreview
	root.add_child(preview)
	await process_frame

	var title := preview.get_node_or_null("MarginContainer/Content/TitlePanel/TitleLabel") as Label
	var type_label := preview.get_node_or_null(
		"MarginContainer/Content/BadgeRow/TypeBadge/TypeLabel"
	) as Label
	var stats_section := preview.get_node_or_null("MarginContainer/Content/StatsSection") as Control
	var stats := preview.get_node_or_null("MarginContainer/Content/StatsSection/Lines") as Label
	var rewards_section := preview.get_node_or_null("MarginContainer/Content/RewardsSection") as Control
	var rewards := preview.get_node_or_null("MarginContainer/Content/RewardsSection/Lines") as Label
	var abilities_section := preview.get_node_or_null("MarginContainer/Content/AbilitiesSection") as Control
	var abilities := preview.get_node_or_null("MarginContainer/Content/AbilitiesSection/Lines") as Label
	_expect(title != null and type_label != null, "preview scene contains title and type labels")
	_expect(stats != null and rewards != null and abilities != null, "preview scene contains all content sections")

	var model := EventHoverPreviewModelScript.new()
	model.visible = true
	model.title = "啮髓鼠群"
	model.type_label = "残响"
	model.stat_lines = ["生命：3 / 10", "护甲：2"]
	model.reward_lines = ["必得：8 金币"]
	model.ability_lines = ["啃食骨髓：造成 2 点伤害。"]
	preview.present(model)

	_expect(preview.visible, "present shows preview")
	_expect(preview.is_presenting(), "present records active preview")
	_expect(title != null and title.text == "啮髓鼠群", "present refreshes title")
	_expect(type_label != null and type_label.text == "残响", "present refreshes type label")
	_expect(stats != null and stats.text.contains("生命：3 / 10"), "present refreshes stat lines")
	_expect(rewards != null and rewards.text.contains("必得：8 金币"), "present refreshes reward lines")
	_expect(abilities != null and abilities.text.contains("啃食骨髓"), "present refreshes ability lines")
	_expect(
		stats_section.visible and rewards_section.visible and abilities_section.visible,
		"present shows every populated content section",
	)

	model.stat_lines = []
	model.reward_lines = []
	model.ability_lines = []
	preview.present(model)
	_expect(
		not stats_section.visible and not rewards_section.visible and not abilities_section.visible,
		"present hides empty content sections without leaving decorative dividers behind",
	)

	preview.dismiss()
	_expect(not preview.visible, "dismiss hides preview")
	_expect(not preview.is_presenting(), "dismiss clears active preview")
	_expect(title != null and title.text.is_empty(), "dismiss clears rendered title")
	preview.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
