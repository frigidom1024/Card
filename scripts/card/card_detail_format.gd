class_name CardDetailFormat
extends RefCounted

const RARITY_NAMES := {
	CardData.Rarity.COMMON: "COMMON",
	CardData.Rarity.RARE: "RARE",
	CardData.Rarity.EPIC: "EPIC",
	CardData.Rarity.LEGENDARY: "LEGENDARY",
}

const CARD_TYPE_NAMES := {
	CardData.CardType.ROOT: "ROOT",
	CardData.CardType.NORMAL: "CARD",
	CardData.CardType.GUIDE: "GUIDE",
}

const TAG_NAMES := {
	CardData.CardTag.WEAPON: "WEAPON",
	CardData.CardTag.DEFENSE: "DEFENSE",
	CardData.CardTag.HEAL: "HEAL",
	CardData.CardTag.RESOURCE: "RESOURCE",
	CardData.CardTag.LOCATION: "LOCATION",
	CardData.CardTag.CREATURE: "CREATURE",
	CardData.CardTag.ITEM: "ITEM",
	CardData.CardTag.EVENT: "EVENT",
	CardData.CardTag.HOLY: "HOLY",
	CardData.CardTag.DARK: "DARK",
	CardData.CardTag.NATURE: "NATURE",
}


static func rarity_name(rarity: CardData.Rarity) -> String:
	return RARITY_NAMES.get(rarity, "UNKNOWN")


static func card_type_name(card_type: CardData.CardType) -> String:
	return CARD_TYPE_NAMES.get(card_type, "UNKNOWN")


static func tag_name(tag: CardData.CardTag) -> String:
	return TAG_NAMES.get(tag, "UNKNOWN")


static func compact_description(text: String, character_limit: int = 120) -> String:
	var compact := text.replace("\n", " ").replace("\r", " ").strip_edges()
	if character_limit <= 0 or compact.length() <= character_limit:
		return compact
	return compact.left(character_limit - 1) + "…"


static func stat_entries(data: CardData) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if data.damage > 0:
		entries.append({"attribute": CardDetailStatSeal.Attribute.DAMAGE, "value": data.damage})
	if data.defense > 0:
		entries.append({"attribute": CardDetailStatSeal.Attribute.DEFENSE, "value": data.defense})
	if data.heal > 0:
		entries.append({"attribute": CardDetailStatSeal.Attribute.HEAL, "value": data.heal})
	return entries