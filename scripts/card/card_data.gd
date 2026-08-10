class_name CardData
extends Resource

enum CardType { ROOT, NORMAL, GUIDE }

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
## Legacy serialized price; MarketPricingService derives the actual price from rarity.
@export_range(1, 999, 1) var value: int = 1
@export_file("*.png", "*.webp", "*.jpg", "*.jpeg") var artwork_path: String = ""
@export var card_type: CardType = CardType.NORMAL

# 战斗属性
## value remains the store price. max_points is the persistent combat value.
@export_range(1, 999, 1) var max_points: int = 1
## Starting armor. Runtime rule effects may increase current armor without a global cap.
@export_range(0, 999, 1) var armor: int = 0
# Legacy combat fields retained until the point-combat migration is complete.
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
