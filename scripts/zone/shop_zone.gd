extends CardZone
class_name ShopZone

var _cards:Array[Card]
var card_anchor_position:Array[Vector2]

@export_group("layout")
@export var paddling:float
@export var interval:float


func _caculate_anchor_postion()->void:
	#计算吸附的点位
	pass

## 该Zone由res://scenes/zone/shop.tscn持有的组件。shop负者维护商店信息，shop负者提供检查玩家是否能
## 从商店区拖拽走卡牌（目前游戏从商店中拖拽卡牌需要玩家持有金币>=卡牌价值
func can_trans_from_source(card: Card) -> bool:
	# TODO
	return false

## 玩家不能将卡牌挪到商店区
func can_trans_to_target(card: Card) -> bool:
	return false


## 卡牌准备迁移到其它区域了，商店可以进行扣除玩家金币了，如果移动失败那么把卡牌位置重新调整到卡牌原来的吸附位置
func drag_end_source(card: Card, ok: bool) -> bool:
	#TODO
	return true
