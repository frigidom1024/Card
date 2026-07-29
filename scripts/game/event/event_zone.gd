class_name EventInstance
extends RefCounted

## 事件模板（引用 EventData 配置）
var template: EventData
## 棋盘格子坐标（左上角）
var origin: Vector2i
## 是否已揭开（玩家发现该事件）
var is_revealed: bool = false
## 是否已解决（战斗胜利/购买完成/奖励已领）
var is_resolved: bool = false


func get_size() -> Vector2i:
	return template.size if template else Vector2i.ONE


func get_event_type() -> int:
	return template.event_type if template else -1


func get_content() -> Resource:
	return template.content if template else null


## 标记事件已完成
func resolve() -> void:
	is_revealed = true
	is_resolved = true
