## 牌桌卡牌拆链操作
##
## 负责描述 BoardZone 已完成的一次牌链空间拆除结果。
## 包括：
## - 玩家直接移出的卡牌
## - 按原牌链顺序返回的后继卡牌
## - 拆除前的牌链长度
##
## 不负责：
## - 将卡牌加入手牌
## - 发放奖励或执行事件结算
## - 管理拖拽协议
##
## 使用方式：
## BoardZone 完成拆链空间提交后填充该对象，并通过 chain_segment_detached 信号发布。
##
## 依赖：
## Card：牌桌上的卡牌视图。
class_name BoardCardRetraction
extends RefCounted


var removed_card: Card
var followers_to_return: Array[Card]
var original_chain_size: int
