extends Node2D

@export var board_padding: Vector2 = Vector2(14.0, 14.0)
@export var board_panel_color: Color = Color(0.35, 0.39, 0.44, 0.14)
@export var grid_line_color: Color = Color(0.35, 0.39, 0.44, 0.36)
@export var grid_line_width: float = 2.0
@export var grid_dash_length: float = 6.0
@export var grid_gap_length: float = 5.0

var board_size: Vector2 = Vector2.ZERO
var cell_size: float = 0.0
var grid_width: int = 0
var grid_height: int = 0


func configure(new_board_size: Vector2, new_cell_size: float, width: int, height: int) -> void:
	board_size = new_board_size
	cell_size = new_cell_size
	grid_width = width
	grid_height = height
	queue_redraw()


func _draw() -> void:
	draw_rect(
		Rect2(-board_padding, board_size + board_padding * 2.0),
		board_panel_color,
		true
	)

	if cell_size <= 0.0 or grid_width <= 0 or grid_height <= 0:
		return
	if grid_dash_length <= 0.0 or grid_gap_length <= 0.0 or grid_line_width <= 0.0:
		return

	var logical_width := float(grid_width) * cell_size
	var logical_height := float(grid_height) * cell_size
	for column in range(grid_width + 1):
		var x := float(column) * cell_size
		_draw_dashed_line(Vector2(x, 0.0), Vector2(x, logical_height))
	for row in range(grid_height + 1):
		var y := float(row) * cell_size
		_draw_dashed_line(Vector2(0.0, y), Vector2(logical_width, y))


func _draw_dashed_line(from: Vector2, to: Vector2) -> void:
	var direction := to - from
	var length := direction.length()
	if length <= 0.0:
		return

	var unit_direction := direction / length
	var offset := 0.0
	var dash_step := grid_dash_length + grid_gap_length
	while offset < length:
		var dash_end := minf(offset + grid_dash_length, length)
		draw_line(
			from + unit_direction * offset,
			from + unit_direction * dash_end,
			grid_line_color,
			grid_line_width,
			true
		)
		offset += dash_step
