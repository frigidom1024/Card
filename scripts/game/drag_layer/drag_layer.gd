extends Node


var dragging_card:Card
var active_zones:Array[Zone]



func _process(delta: float) -> void:
	pass

func _on_dragging_start(card:Card)->void:
	dragging_card=card

func _on_dragging_end(card:Card)->void:
	dragging_card=null
