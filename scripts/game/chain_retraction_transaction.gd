## 牌链回收业务事务
##
## 负责记录一次已完成的玩家主动拆链业务结果。
## 包括：
## - 玩家直接移出的卡牌
## - 已返回手牌的后继卡牌
## - 拆除前的牌链长度
##
## 不负责：
## - 修改 BoardZone 格子
## - 将卡牌实际加入手牌
## - 处理拖拽合法性
##
## 使用方式：
## Board 在所有后继卡牌同步返回手牌后构造并发布该事务。
##
## 依赖：
## Card：公开卡牌视图。
class_name ChainRetractionTransaction
extends RefCounted


var removed_card: Card
var returned_followers: Array[Card]
var original_chain_size: int


func _init(
	removed = null,
	followers: Array = [],
	chain_size: int = 0
) -> void:
	removed_card = removed as Card
	returned_followers.clear()
	for follower in followers:
		if follower is Card:
			returned_followers.append(follower)
	original_chain_size = chain_size
