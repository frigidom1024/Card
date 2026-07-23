extends Control

var card_data:CardData
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_card_data(new_data:CardData):
	card_data=new_data

func get_card_data()->CardData:
	return card_data


func _on_gui_input(event: InputEvent) -> void:
	pass # Replace with function body.
