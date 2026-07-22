extends Area2D

var dragging:bool= false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if dragging:
		global_position = get_global_mouse_position()


func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		elif  event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				rotation_degrees+=90
				if rotation_degrees>=360:
					rotation_degrees=0
