extends ColorRect

@export var line_width := 2
@export var dash_length := 6
@export var gap_length := 4

func _draw():
	var y := 0.0
	while y < size.y:
		var length = min(dash_length, size.y - y)
		draw_rect(
			Rect2(0, y, line_width, length),
			Color.BLACK
		)
		y += dash_length + gap_length

func _ready() -> void:
	color = Color(1, 1, 1, 0)
