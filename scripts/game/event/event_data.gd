class_name EventData
extends Resource

enum EventType {
	SHOP,
	TREASURE,
	MONSTER,
	BOSS,
}


@export var event_id: String
@export var event_type: EventType

## 占用棋盘大小
@export var size: Vector2i = Vector2i.ONE

## 显示资源
@export var icon: Texture2D

## 具体事件配置（多态，各类型不同）
@export var content: Resource


## 从模板创建运行时实例
func create_instance() -> EventInstance:
	var inst = EventInstance.new()
	inst.template = self
	inst.origin = Vector2i(-1,-1)
	return inst
