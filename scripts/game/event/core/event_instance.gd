class_name EventInstance
extends RefCounted

const EventDataScript = preload("res://scripts/game/event/core/event_data.gd")
const TreasureRewardOptionScript = preload("res://scripts/game/event/treasure_reward_option.gd")

## 事件模板（引用 EventData 配置）
var template: EventDataScript
## 棋盘格子坐标（左上角）
var origin: Vector2i
## 是否已揭开（玩家发现该事件）
var is_revealed: bool = false
## 是否已解决（战斗胜利/购买完成/奖励已领）
var is_resolved: bool = false
## 每个事件实例的可扩展运行时状态。
var runtime_state: EventRuntimeState

## 此事件已经生成的宝藏选项，重复打开时不重新抽取。
var treasure_options: Array[TreasureRewardOptionScript] = []
## 已领取的宝藏选项索引；未领取时为 -1。
var selected_treasure_option := -1


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