class_name EventHoverPreview
extends PanelContainer

var _current_model: EventHoverPreviewModel

@onready var _title_label: Label = $MarginContainer/Content/TitlePanel/TitleLabel
@onready var _type_label: Label = $MarginContainer/Content/BadgeRow/TypeBadge/TypeLabel
@onready var _stats_section: Control = $MarginContainer/Content/StatsSection
@onready var _stats_lines: Label = $MarginContainer/Content/StatsSection/Lines
@onready var _rewards_section: Control = $MarginContainer/Content/RewardsSection
@onready var _rewards_lines: Label = $MarginContainer/Content/RewardsSection/Lines
@onready var _abilities_section: Control = $MarginContainer/Content/AbilitiesSection
@onready var _abilities_lines: Label = $MarginContainer/Content/AbilitiesSection/Lines



func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _current_model != null:
		_apply_model(_current_model)
	else:
		dismiss()


func present(model: EventHoverPreviewModel) -> void:
	if model == null or not model.visible:
		dismiss()
		return
	_current_model = model
	if not is_node_ready():
		return
	_apply_model(model)
	show()


func dismiss() -> void:
	_current_model = null
	if not is_node_ready():
		return
	_title_label.text = ""
	_type_label.text = ""
	_set_section_lines(_stats_section, _stats_lines, [])
	_set_section_lines(_rewards_section, _rewards_lines, [])
	_set_section_lines(_abilities_section, _abilities_lines, [])
	hide()


func is_presenting() -> bool:
	return _current_model != null and visible


func _apply_model(model: EventHoverPreviewModel) -> void:
	_title_label.text = model.title
	_type_label.text = model.type_label
	_set_section_lines(_stats_section, _stats_lines, model.stat_lines)
	_set_section_lines(_rewards_section, _rewards_lines, model.reward_lines)
	_set_section_lines(_abilities_section, _abilities_lines, model.ability_lines)


func _set_section_lines(section: Control, label: Label, lines: Array[String]) -> void:
	var has_lines := not lines.is_empty()
	section.visible = has_lines
	label.text = "\n".join(lines) if has_lines else ""
