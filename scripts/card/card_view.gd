extends ColorRect

@onready var labelcontainer = $LabelContainer

var card_inst:CardInstance

func _ready() -> void:
	if not card_inst:
		card_inst = CardInstance.create_debug_card()
	resized.connect(_pin_label_container)
	_pin_label_container()
	refresh_display()


func _pin_label_container() -> void:
	var h := size.y
	labelcontainer.offset_left = 0.5
	labelcontainer.offset_top = h - 23.0
	labelcontainer.offset_right = size.x - 0.5
	labelcontainer.offset_bottom = h


func refresh_display():
	_update_battle_attr_label()


func set_value(value: CardInstance):
	card_inst = value
	refresh_display()


func _update_battle_attr_label():
	for child in labelcontainer.get_children():
		child.queue_free()

	var data := card_inst.card_data
	for entry in [
		{"value": data.damage,  "icon": "⚔", "color": Color("red")},
		{"value": data.defense, "icon": "🛡", "color": Color("yellow")},
		{"value": data.heal,    "icon": "❤", "color": Color("green")},
	]:
		if entry.value>0:
			var label := Label.new()
			label.text = entry.icon + str(entry.value)
			label.modulate = entry.color
			labelcontainer.add_child(label)
