class_name MobActionResolver
extends RefCounted


static func to_effects(
	action: MobAction, source_name: String, enhancement_bonus: int = 0
) -> Array[CombatEffect]:
	match action.type:
		MobAction.Type.ATTACK:
			return [
				CombatEffect.new(
					CombatEffect.Type.DAMAGE,
					CombatEffect.Target.PLAYER,
					action.value + enhancement_bonus,
					CombatEffect.SourceType.MONSTER_ACTION,
					source_name
				)
			]
		MobAction.Type.DEFEND:
			return [
				CombatEffect.new(
					CombatEffect.Type.ADD_DEFENSE,
					CombatEffect.Target.MONSTER,
					action.value + enhancement_bonus,
					CombatEffect.SourceType.MONSTER_ACTION,
					source_name
				)
			]
		MobAction.Type.HEAL:
			return [
				CombatEffect.new(
					CombatEffect.Type.HEAL,
					CombatEffect.Target.MONSTER,
					action.value + enhancement_bonus,
					CombatEffect.SourceType.MONSTER_ACTION,
					source_name
				)
			]
		_:
			return []
