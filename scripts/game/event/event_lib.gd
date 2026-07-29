class_name EventLib
extends Resource

@export var entries: Array[EventEntry] = []
@export var event_scene:PackedScene
# 提供给外部的事件生成
func generate_event_datas() -> Array[EventInstance]:
	var datas: Array[EventInstance] = []
	for entry in entries:
		var count = randi_range(entry.min_count, entry.max_count)
		for i in count:
			datas.append(entry.event_data.create_instance())
	return datas


func create_event_scene(event_inst: EventInstance, cell_size: int) -> BoardEvent:
	if event_scene == null or event_inst == null:
		return null
	var board_event := event_scene.instantiate() as BoardEvent
	if board_event == null:
		return null
	board_event.setup(event_inst, cell_size)
	return board_event
