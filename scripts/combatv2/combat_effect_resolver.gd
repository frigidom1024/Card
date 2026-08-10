class_name CombatEffectResolver
extends RefCounted

const CombatEffectDraftScript = preload("res://scripts/combatv2/combat_effect_draft.gd")


## Applies the pending CombatEffect list in order and returns the same effects
## enriched with accounting fields for logs and animation playback.
func resolve(draft) -> Array[CombatEffect]:
	var resolved: Array[CombatEffect] = []
	if draft == null:
		return resolved
	for effect in draft.effects:
		if effect == null:
			continue
		_apply_effect(effect, draft)
		resolved.append(effect)
	return resolved


func resolve_effects(effects: Array[CombatEffect], context: CombatContext, current_card: CardInstance = null) -> Array[CombatEffect]:
	var draft = CombatEffectDraftScript.new(context, current_card)
	for effect in effects:
		draft.add_effect(effect)
	return resolve(draft)


func _apply_effect(effect: CombatEffect, draft) -> void:
	if effect.cancelled:
		_set_accounting(effect, 0, 0, 0, false)
		effect.set_parameter("skipped_reason", "cancelled")
		return
	match effect.type:
		CombatEffect.Type.DAMAGE:
			_apply_damage(effect, draft)
		CombatEffect.Type.ADD_DEFENSE:
			_apply_defense(effect, draft)
		CombatEffect.Type.HEAL:
			_apply_heal(effect, draft)
		CombatEffect.Type.MODIFY_CARD_POINTS:
			_apply_card_points(effect, draft)
		_:
			_set_accounting(effect, 0, 0, 0, false)
			effect.set_parameter("skipped_reason", "unsupported_type")


func _apply_damage(effect: CombatEffect, draft) -> void:
	var incoming := maxi(effect.value, 0)
	var applied := 0
	var absorbed := 0
	var resolved := false
	match effect.target:
		CombatEffect.Target.MONSTER:
			var monster_stats: CombatStats = draft.combat_context.monster.stats if draft.combat_context != null and draft.combat_context.monster != null else null
			if monster_stats != null:
				_record_stats_before(effect, monster_stats)
				var defense_before := monster_stats.defense
				applied = draft.combat_context.monster.take_damage(incoming)
				absorbed = maxi(defense_before - monster_stats.defense, 0)
				_record_stats_after(effect, monster_stats)
				resolved = true
		CombatEffect.Target.PLAYER:
			var player_stats: CombatStats = draft.combat_context.player_stats if draft.combat_context != null else null
			if player_stats != null:
				_record_stats_before(effect, player_stats)
				var defense_before := player_stats.defense
				applied = player_stats.take_damage(incoming)
				absorbed = maxi(defense_before - player_stats.defense, 0)
				_record_stats_after(effect, player_stats)
				resolved = true
		CombatEffect.Target.CARD:
			var card: CardInstance = effect.target_card if effect.target_card != null else draft.current_card
			if card != null:
				effect.set_parameter("card_points_before", card.current_points)
				effect.set_parameter("card_armor_before", card.current_armor)
				var armor_multiplier := maxf(float(effect.get_parameter("armor_multiplier", 1.0)), 0.0)
				var point_multiplier := maxf(float(effect.get_parameter("point_multiplier", 1.0)), 0.0)
				var armor_damage := int(ceil(float(incoming) * armor_multiplier))
				absorbed = card.consume_armor(armor_damage)
				# Armor multiplier changes how quickly armor is broken, not the incoming hit itself.
				var blocked_damage := float(absorbed) / armor_multiplier if armor_multiplier > 0.0 else 0.0
				var point_damage := int(ceil(maxf(float(incoming) - blocked_damage, 0.0) * point_multiplier))
				applied = card.consume_points(point_damage)
				effect.set_parameter("card_points_after", card.current_points)
				effect.set_parameter("card_armor_after", card.current_armor)
				resolved = true
	_set_accounting(effect, absorbed, applied, absorbed + applied, resolved)


func _apply_card_points(effect: CombatEffect, draft) -> void:
	var card: CardInstance = effect.target_card if effect.target_card != null else draft.current_card
	if card == null:
		_set_accounting(effect, 0, 0, 0, false)
		return
	var points_before := card.current_points
	var delta := effect.value
	var changed := card.add_points(delta) if delta >= 0 else card.consume_points(-delta)
	effect.set_parameter("card_points_before", points_before)
	effect.set_parameter("card_points_after", card.current_points)
	effect.set_parameter("point_delta", delta)
	if delta > 0 and bool(effect.get_parameter("temporary", false)) and draft.combat_context != null:
		draft.combat_context.register_temporary_card_points(card, changed)
	_set_accounting(effect, 0, changed, changed, true)


func _record_stats_before(effect: CombatEffect, stats: CombatStats) -> void:
	effect.set_parameter("hp_before", stats.hp)
	effect.set_parameter("defense_before", stats.defense)


func _record_stats_after(effect: CombatEffect, stats: CombatStats) -> void:
	effect.set_parameter("hp_after", stats.hp)
	effect.set_parameter("defense_after", stats.defense)


func _apply_defense(effect: CombatEffect, draft) -> void:
	var granted := maxi(effect.value, 0)
	var applied := 0
	var resolved := false
	match effect.target:
		CombatEffect.Target.MONSTER:
			if draft.combat_context != null and draft.combat_context.monster != null and draft.combat_context.monster.stats != null:
				_record_stats_before(effect, draft.combat_context.monster.stats)
				draft.combat_context.monster.stats.add_defense(granted)
				applied = granted
				_record_stats_after(effect, draft.combat_context.monster.stats)
				resolved = true
		CombatEffect.Target.PLAYER:
			if draft.combat_context != null and draft.combat_context.player_stats != null:
				_record_stats_before(effect, draft.combat_context.player_stats)
				draft.combat_context.player_stats.add_defense(granted)
				applied = granted
				_record_stats_after(effect, draft.combat_context.player_stats)
				resolved = true
		CombatEffect.Target.CARD:
			var card: CardInstance = effect.target_card if effect.target_card != null else draft.current_card
			if card != null:
				effect.set_parameter("card_armor_before", card.current_armor)
				applied = card.add_armor(granted)
				effect.set_parameter("card_armor_after", card.current_armor)
				resolved = true
	_set_accounting(effect, 0, applied, applied, resolved)


func _apply_heal(effect: CombatEffect, draft) -> void:
	var restored := 0
	var resolved := false
	match effect.target:
		CombatEffect.Target.MONSTER:
			if draft.combat_context != null and draft.combat_context.monster != null and draft.combat_context.monster.stats != null:
				var monster_stats: CombatStats = draft.combat_context.monster.stats
				_record_stats_before(effect, monster_stats)
				restored = monster_stats.heal(effect.value)
				_record_stats_after(effect, monster_stats)
				resolved = true
		CombatEffect.Target.PLAYER:
			if draft.combat_context != null and draft.combat_context.player_stats != null:
				var player_stats: CombatStats = draft.combat_context.player_stats
				_record_stats_before(effect, player_stats)
				restored = player_stats.heal(effect.value)
				_record_stats_after(effect, player_stats)
				resolved = true
	_set_accounting(effect, 0, restored, restored, resolved)


func _set_accounting(effect: CombatEffect, absorbed: int, applied: int, total: int, resolved: bool) -> void:
	effect.set_parameter("absorbed", maxi(absorbed, 0))
	effect.set_parameter("applied", maxi(applied, 0))
	effect.set_parameter("total", maxi(total, 0))
	effect.set_parameter("resolved", resolved)
