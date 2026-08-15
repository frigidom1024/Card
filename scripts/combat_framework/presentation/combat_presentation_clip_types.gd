class_name CombatPresentationClipTypes
extends RefCounted

const CARD_TRIGGER: StringName = &"card_trigger"
const CARD_ATTACK: StringName = &"card_attack"
const CARD_HIT: StringName = &"card_hit"
const CARD_POINTS_CHANGE: StringName = &"card_points_change"
const CARD_SHIELD_CHANGE: StringName = &"card_shield_change"
const CARD_DEATH: StringName = &"card_death"

const MONSTER_ATTACK: StringName = &"monster_attack"
const MONSTER_HIT: StringName = &"monster_hit"
const MONSTER_HEALTH_CHANGE: StringName = &"monster_health_change"
const MONSTER_SHIELD_CHANGE: StringName = &"monster_shield_change"
const MONSTER_DEATH: StringName = &"monster_death"

const CHAIN_SPLIT: StringName = &"chain_split"
const CHAIN_REFLOW: StringName = &"chain_reflow"

const GOLD_CHANGE: StringName = &"gold_change"
const PLAYER_HEALTH_CHANGE: StringName = &"player_health_change"

const MAIN_BATTLE: StringName = &"main_battle"
const PLAYER_OPERATION: StringName = &"player_operation"


static func entity_lock(entity_id: String) -> StringName:
	return StringName("entity:%s" % entity_id)
