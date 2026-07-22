extends Area2D


enum CardState {
	NORMAL,     # 普通
	HOVER,      # 悬浮
	DRAGGING    # 拖拽
}


var state: CardState = CardState.NORMAL


func _ready() -> void:
	input_pickable = true



func _process(delta: float) -> void:

	if state == CardState.DRAGGING:
		global_position = get_global_mouse_position()



func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:

	if event is InputEventMouseButton:

		# 左键
		if event.button_index == MOUSE_BUTTON_LEFT:

			if event.pressed:
				change_state(CardState.DRAGGING)
			else:
				change_state(CardState.NORMAL)


		# 右键
		elif event.button_index == MOUSE_BUTTON_RIGHT:

			if event.pressed:
				rotate_card()



func change_state(new_state: CardState):

	state = new_state

	match state:

		CardState.NORMAL:
			z_index = 0
			scale = Vector2.ONE


		CardState.HOVER:
			scale = Vector2(1.1, 1.1)


		CardState.DRAGGING:
			z_index = 10
			scale = Vector2(1.1, 1.1)



func rotate_card():

	rotation_degrees += 90

	if rotation_degrees >= 360:
		rotation_degrees = 0


func _on_mouse_entered():

	if state == CardState.NORMAL:
		change_state(CardState.HOVER)

func _on_mouse_exited():

	if state == CardState.HOVER:
		change_state(CardState.NORMAL)
