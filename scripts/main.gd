extends Node2D

@onready var background_fill: ColorRect = $BackgroundLayer/BackgroundFill


func _ready() -> void:
	DisplayServer.window_set_min_size(LayoutConfig.MIN_WINDOW_SIZE)
	_fit_background_to_viewport()

	var viewport := get_viewport()
	if not viewport.size_changed.is_connected(_fit_background_to_viewport):
		viewport.size_changed.connect(_fit_background_to_viewport)


## 背景独立于 GameplayCanvas：始终覆盖当前窗口，而玩法内容仍保持等比缩放。
func _fit_background_to_viewport() -> void:
	background_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
