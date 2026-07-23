extends Area2D


var board: Node2D

var card_data:CardData
enum CardState {
	NORMAL,
	HOVER,
	DRAGGING
}

var state: CardState = CardState.NORMAL

# 卡牌方向
var direction := 0
# 0 横向
# 1 纵向
# 2 横向反
# 3 纵向反

func set_board(target_board:Node2D):
	board = target_board

func _ready() -> void:
	input_pickable = true

# =====================
# 拖拽
# =====================
func _process(delta):

	if state == CardState.DRAGGING:

		global_position = get_global_mouse_position()

		# 拖动预览
		if board:

			board.preview_card(
				global_position,
				rotation_degrees
			)

# =====================
# 鼠标输入
# =====================

func _on_input_event(
	viewport: Node,
	event: InputEvent,
	shape_idx: int
):

	if event is InputEventMouseButton:


		# 左键
		if event.button_index == MOUSE_BUTTON_LEFT:


			if event.pressed:

				change_state(
					CardState.DRAGGING
				)


			else:

				drop_card()



		# 右键
		elif event.button_index == MOUSE_BUTTON_RIGHT:


			if event.pressed and state==CardState.DRAGGING:

				rotate_card()





# =====================
# 状态
# =====================

func change_state(new_state:CardState):

	state = new_state


	match state:


		CardState.NORMAL:

			z_index = 0
			modulate = Color.WHITE



		CardState.HOVER:

			z_index = 1
			modulate = Color(1.1,1.1,1.1)



		CardState.DRAGGING:

			z_index = 10
			modulate = Color(1.2,1.2,1)



# =====================
# 放置
# =====================


func drop_card():


	if board:


		var cells = board.get_card_cells(
			global_position,
			rotation_degrees
		)


		if board.can_place_card(cells):


			global_position = board.snap_card_position(
				global_position,
				rotation_degrees
			)


		else:

			print("无法放置")


		board.clear_preview()



	change_state(
		CardState.NORMAL
	)





# =====================
# 旋转
# =====================

func rotate_card():


	direction = (
		direction + 1
	) % 4


	rotation_degrees = direction * 90



	# 拖动时刷新预览

	if state == CardState.DRAGGING and board:

		board.preview_card(
			global_position,
			rotation_degrees
		)





# =====================
# 悬浮
# =====================

func _on_mouse_entered():

	if state == CardState.NORMAL:

		change_state(
			CardState.HOVER
		)



func _on_mouse_exited():

	if state == CardState.HOVER:

		change_state(
			CardState.NORMAL
		)
