class_name BoardEvent
extends Control

signal event_selected(instance: EventInstance)

var event_instance: EventInstance
var _cell_size := 80

func setup(instance: EventInstance, cell_size: int) -> void:
	event_instance = instance
	_cell_size = cell_size
	position = Vector2(instance.origin * cell_size)
	size = Vector2(instance.get_size() * cell_size)
	custom_minimum_size = size
	if is_node_ready():
		_refresh()

func _ready() -> void:
	_refresh()

func _refresh() -> void:
	pass
