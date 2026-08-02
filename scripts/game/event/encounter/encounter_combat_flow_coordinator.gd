class_name EncounterCombatFlowCoordinator
extends RefCounted

var _encounter_resolver := EncounterEventResolver.new()
var _combat_service: CombatService2


func _init(combat_service: CombatService2 = null) -> void:
	_combat_service = combat_service if combat_service != null else CombatService2.new()


func begin(instance: EventInstance) -> MobInstance:
	return _encounter_resolver.begin(instance)


func resolve(
	player_stats: CombatStats,
	card_chain: Array[CardInstance],
	monster: MobInstance
) -> CombatResult:
	if monster == null:
		return null
	return _combat_service.resolve_encounter(player_stats, card_chain, monster)
