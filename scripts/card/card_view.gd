extends ColorRect
@onready  var labelcontainer = $LabelContainer

var card_inst:CardInstance
@export var battle_attr_label:PackedScene
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	card_inst=CardInstance.create_debug_card()
	refresh_display()
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# 刷新数据并渲染
func refresh_display():
	_update_battle_attr_label()
	
func set_value(value:CardInstance):
	card_inst=value

func _update_battle_attr_label():
	for child in labelcontainer.get_children():
		child.queue_free()

	for attr in _get_battle_attrs():
		_add_attr(attr.value, attr.type)


func _get_battle_attrs() -> Array[Dictionary]:
	var data = card_inst.card_data
	return [
		{"value": data.damage, "type": "damage"},
		{"value": data.heal, "type": "heal"},
		{"value": data.defense, "type": "defense"},
	]


func _add_attr(value: int, type: String):
	if value <= 0:
		return
	var label = battle_attr_label.instantiate()
	label.set_and_refresh(value, type)
	labelcontainer.add_child(label)
