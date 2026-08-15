class_name CombatMonsterDeathStateRule
extends CombatStateRule


func evaluate(_effect: CombatBatchEffect, writer: CombatStateWriter) -> CombatValidationResult:
	if not bool(writer.get_value(["monster", "alive"], false)):
		return CombatValidationResult.accepted()
	if int(writer.get_value(["monster", "hp"], 0)) > 0:
		return CombatValidationResult.accepted()
	var monster_id := str(writer.get_value(["monster", "entity_id"], "monster"))
	writer.set_value(["monster", "alive"], false, CombatEventTypes.MONSTER_DIED, monster_id, {
		"monster_id": monster_id,
	})
	return CombatValidationResult.accepted()
