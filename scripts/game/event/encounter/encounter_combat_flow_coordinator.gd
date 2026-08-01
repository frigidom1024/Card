class_name EncounterCombatFlowCoordinator
extends RefCounted

var _encounter_resolver := EncounterEventResolver.new()
var _combat_service_router := CombatServiceRouter.new()


func begin(instance: EventInstance) -> MobInstance:
	return _encounter_resolver.begin(instance)


func resolve(
	player_stats: CombatStats,
	card_chain: Array[CardInstance],
	monster: MobInstance
) -> CombatResult:
	if monster == null:
		return null
	return _combat_service_router.resolve(player_stats, card_chain, monster)
