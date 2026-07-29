class_name MobAction
extends Resource

## 行动类型
enum Type {
	ATTACK,   # 攻击玩家
	DEFEND,   # 给自己加防御
	HEAL,     # 治疗自己
	BUFF,     # 强化
	DEBUFF,   # 弱化玩家
	SPECIAL,  # 特殊技能
}

## 行动类型
@export var type: Type = Type.ATTACK
## 数值参数（伤害量/治疗量/防御值等）
@export var value: int = 1
## 行动描述（用于 UI 展示）
@export var description: String = ""
## 可选：对应的卡牌数据（复用卡牌图标/效果）
@export var card_data: CardData = null
