class_name CombatPenaltyRemoveTailCard
extends CombatPenalty

func _init() -> void:
	self.type=Type.REMOVE_TAIL_CARD
	self.description="移除牌桌上牌链上最后一张卡牌"


func execute(context:PenaltyContext)->bool:
	var cards_on_board = context.cards_on_board
	if cards_on_board.size()>1:
		cards_on_board.pop_back()
	return true
