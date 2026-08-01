extends RefCounted
class_name CombatAction

enum TYPE{PLAYER,MONSTER}

#玩家/怪物 第几轮行动
#对于玩家可以作为是来源卡牌在牌链中的位置
var index:int
var type:TYPE
func _init(type:TYPE,index:int) -> void:
	self.type=type
	self.index=index
