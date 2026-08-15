extends Control

@export var attr_label:PackedScene
@onready var attr_container=$Panel/MarginContainer/HBoxContainer
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

var card_inst:CardInstance

func set_inst(card_inst:CardInstance)->void:
	card_inst=card_inst

func refresh_info() ->void:
	for child in attr_container.get_children():
		child.queue_free()
	
	var attr1 = attr_label.instantiate()
	var text = "point:%d	armor:%d" % [card_inst.current_points,card_inst.current_armor]
	attr1.set_content(text)
	attr_container.add_child(attr1)
	
	for rule in card_inst.card_data.effect_rules:
		var attr  =attr_label.instantiate()
		attr.set_content(rule.description)
		attr_container.add_child(attr)
	return
