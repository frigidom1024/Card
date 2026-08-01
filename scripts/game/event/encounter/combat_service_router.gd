class_name CombatServiceRouter
extends RefCounted


func resolve(
	player_stats: CombatStats,
	card_chain: Array[CardInstance],
	monster: MobInstance
) -> CombatResult:
	return CombatService2.new().resolve_encounter(player_stats, card_chain, monster)
