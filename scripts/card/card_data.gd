class_name CardData
extends Resource

enum CardType { ROOT, NORMAL }

enum CardTag {
	# 功能
	WEAPON,
	DEFENSE,
	HEAL,
	RESOURCE,
	# 类型
	LOCATION,
	CREATURE,
	ITEM,
	EVENT,
	# 位面
	HOLY,
	DARK,
	NATURE,
}

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

@export var card_id: int = 0
@export var card_name: String = ""
@export var card_type: CardType = CardType.NORMAL

# 战斗属性
@export var damage: int = 0
@export var defense: int = 0
@export var heal: int = 0
@export var effect_rules: Array[CardRule] = []

# 描述
@export_multiline var description: String = ""

# 标签
@export var tags: Array[CardTag] = []

# 稀有度
@export var rarity: Rarity = Rarity.COMMON
