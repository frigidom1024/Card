class_name EventLib
extends Resource

@export var entries: Array[EventEntry] = []

# 提供给外部的事件生成
func generate_event_datas() -> Array[EventData]:
	var datas: Array[EventData] = []
	for entry in entries:
		var count = randi_range(entry.min_count, entry.max_count)
		for i in count:
			datas.append(entry.event_data)
	return datas
