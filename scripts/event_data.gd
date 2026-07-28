class_name EventData
extends Resource
enum EventType { SHOP, TREASURE, MONSTER, BOSS,}

@export var event_type: EventType
@export var size: Vector2i            # 宽×高，如 (1,1)、(2,2)、(1,2)
