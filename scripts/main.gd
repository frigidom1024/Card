extends Node2D

@onready var board = $Board
@onready var card = $Card


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	card.set_board(board)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
