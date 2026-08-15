class_name GameInfo
extends Panel

var _current_hp := 0
var _max_hp := 1
var _current_gold := 0


func _ready() -> void:
	_set_mouse_transparent(self)
	_update_vitality_label()
	_update_gold_label()


func set_vitality(current_hp: int, max_hp: int) -> void:
	_max_hp = maxi(1, max_hp)
	_current_hp = clampi(current_hp, 0, _max_hp)
	_update_vitality_label()


func set_gold(current_gold: int) -> void:
	_current_gold = maxi(0, current_gold)
	_update_gold_label()


func _update_vitality_label() -> void:
	var health_number := get_node_or_null("HeartContainer/HealthNumber") as Label
	if health_number != null:
		health_number.text = "%d / %d" % [_current_hp, _max_hp]


func _update_gold_label() -> void:
	var gold_number := get_node_or_null("GoldNumber") as Label
	if gold_number != null:
		gold_number.text = str(_current_gold)


func _set_mouse_transparent(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_transparent(child)
