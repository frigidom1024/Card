class_name CombatEventTypes
extends RefCounted

## 批次生命周期事件。
const BATCH_STARTED: StringName = &"batch_started"
const BATCH_FINISHED: StringName = &"batch_finished"
const BATCH_CANCELED: StringName = &"batch_canceled"
const BATCH_FAILED: StringName = &"batch_failed"
const EFFECT_APPLIED: StringName = &"effect_applied"

## 玩家攻击和怪物攻击必须使用不同的协议事件。
const PLAYER_ATTACK_STARTED: StringName = &"player_attack_started"
const PLAYER_ATTACK_FINISHED: StringName = &"player_attack_finished"
const MONSTER_ATTACK_STARTED: StringName = &"monster_attack_started"
const MONSTER_ATTACK_FINISHED: StringName = &"monster_attack_finished"

const CARD_TRIGGER_STARTED: StringName = &"card_trigger_started"
const CARD_TRIGGER_FINISHED: StringName = &"card_trigger_finished"
const PLAYER_OPERATION_STARTED: StringName = &"player_operation_started"
const PLAYER_OPERATION_FINISHED: StringName = &"player_operation_finished"
const BATTLE_STARTED: StringName = &"battle_started"
const BATTLE_FINISHED: StringName = &"battle_finished"
const STATE_VALUE_CHANGED: StringName = &"state_value_changed"
const CHAIN_CHANGED: StringName = &"chain_changed"
const PHASE_CHANGED: StringName = &"phase_changed"

## 标准效果状态事件。表现层只消费这些事实，不直接写战斗状态。
const DAMAGE_APPLIED: StringName = &"damage_applied"
const SHIELD_CHANGED: StringName = &"shield_changed"
const HEALTH_CHANGED: StringName = &"health_changed"
const CARD_POINTS_CHANGED: StringName = &"card_points_changed"
const GOLD_CHANGED: StringName = &"gold_changed"
const CHAIN_SPLIT: StringName = &"chain_split"
const CARD_DIED: StringName = &"card_died"
const MONSTER_DIED: StringName = &"monster_died"
