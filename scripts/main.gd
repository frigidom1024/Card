extends Node2D

@onready var board = $Board
@onready var cardManager = $CardManager


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	cardManager.set_board(board)
	cardManager.create_card(
		Vector2(300,300)
	)

	cardManager.create_card(
		Vector2(500,300)
	)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
