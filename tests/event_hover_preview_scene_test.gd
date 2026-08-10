extends SceneTree

const EventHoverPreviewScene = preload("res://scenes/game/event_hover_preview.tscn")
const EventHoverPreviewModelScript = preload(
	"res://scripts/game/event/hover/event_hover_preview_model.gd"
)

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_preview_scene_displays_and_dismisses_model()
	quit(1 if _failure_count > 0 else 0)


func _test_preview_scene_displays_and_dismisses_model() -> void:
	var preview = EventHoverPreviewScene.instantiate()
	root.add_child(preview)
	await process_frame

	var title := preview.get_node_or_null("MarginContainer/Content/Header/TitleLabel") as Label
	var type := preview.get_node_or_null("MarginContainer/Content/Header/TypeLabel") as Label
	var stats := preview.get_node_or_null("MarginContainer/Content/StatsSection/Lines") as Label
	var rewards := preview.get_node_or_null("MarginContainer/Content/RewardsSection/Lines") as Label
	var abilities := preview.get_node_or_null("MarginContainer/Content/AbilitiesSection/Lines") as Label
	_expect(title != null and type != null, "preview scene contains title and type labels")
	_expect(stats != null and rewards != null and abilities != null, "preview scene contains all content sections")
	_expect(preview.mouse_filter == Control.MOUSE_FILTER_IGNORE, "preview root ignores pointer input")

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
	_expect(type != null and type.text == "残响", "present refreshes type label")
	_expect(stats != null and stats.text.contains("生命：3 / 10"), "present refreshes stat lines")
	_expect(rewards != null and rewards.text.contains("必得：8 金币"), "present refreshes reward lines")
	_expect(abilities != null and abilities.text.contains("啃食骨髓"), "present refreshes ability lines")

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
