## 牌桌卡牌放置操作
##
## 负责描述 BoardZone 已完成的一次卡牌空间放置结果。
## 包括：
## - 放置类型与精确 Card/CardInstance
## - 本次占用的格子
## - 受影响的卡牌与牌链尾部
##
## 不负责：
## - 执行格子写入
## - 结算事件或返回手牌
## - 管理卡牌生命周期
##
## 使用方式：
## BoardZone 完成同步空间提交后填充该对象，并通过 placement_applied 信号发布。
##
## 依赖：
## Card：卡牌视图；CardInstance：卡牌运行时状态。
class_name BoardCardPlacement
extends RefCounted


enum Kind {
	CHAIN_EXTENDED,
	GUIDE_SHIFTED,
}

var card: Card
var card_inst: CardInstance
var kind: Kind
var occupied_cells: Array[Vector2i]
var affected_cards: Array[Card]
var chain_tail: Card
