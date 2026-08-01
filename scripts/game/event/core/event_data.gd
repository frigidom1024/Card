class_name EventData
extends Resource

const EventContentScript = preload("res://scripts/game/event/core/event_content.gd")
const EventInstanceScript = preload("res://scripts/game/event/core/event_instance.gd")
const EventRuntimeStateScript = preload("res://scripts/game/event/core/event_runtime_state.gd")

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
@export var content: EventContentScript


## 从模板创建运行时实例
func create_instance() -> EventInstanceScript:
	var instance := EventInstanceScript.new()
	instance.template = self
	instance.origin = Vector2i(-1, -1)
	instance.runtime_state = content.create_runtime_state() if content else EventRuntimeStateScript.new()
	return instance
