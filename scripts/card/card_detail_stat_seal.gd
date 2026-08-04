class_name CardDetailStatSeal
extends PanelContainer

enum Attribute { DAMAGE, DEFENSE, HEAL }

const CONFIG := {
	Attribute.DAMAGE: {
		"label": "STRIKE",
		"background": Color("6f3938"),
		"border": Color("a45a50"),
	},
	Attribute.DEFENSE: {
		"label": "GUARD",
		"background": Color("29465e"),
		"border": Color("5f87a6"),
	},
	Attribute.HEAL: {
		"label": "MEND",
		"background": Color("28594f"),
		"border": Color("579785"),
	},
}

@onready var value_label: Label = $ValueLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(attribute: Attribute, value: int) -> void:
	var config: Dictionary = CONFIG.get(attribute, CONFIG[Attribute.DAMAGE])
	value_label.text = "%d %s" % [value, config["label"]]
	value_label.add_theme_color_override("font_color", Color("eee5cf"))

	var base_style := get_theme_stylebox("panel") as StyleBoxFlat
	var style := base_style.duplicate() as StyleBoxFlat if base_style else StyleBoxFlat.new()
	style.bg_color = config["background"]
	style.border_color = config["border"]
	add_theme_stylebox_override("panel", style)