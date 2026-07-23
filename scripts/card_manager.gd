extends Node2D

@export var card_scene:PackedScene
var board:Node2D

var cards:Array[Area2D]=[]
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_board(target_board:Node2D)->void:
	board=target_board

func create_card(pos:Vector2):

	var card = card_scene.instantiate()
	add_child(card)
	card.global_position = pos
	cards.append(card)
	if board:
		card.set_board(board)
	return card



func remove_card(card):
	if card in cards:
		cards.erase(card)
		card.queue_free()
	
