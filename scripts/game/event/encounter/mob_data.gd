class_name MobData
extends Resource

@export var mob_name: String = ""
@export var base_stats: CombatStatsData
@export var actions: Array[MobAction] = []
@export var gold_reward: int = 0
@export var card_rewards: Array[CardData] = []
## Each failed encounter restores this many HP and raises the echo's maximum HP
## by the same amount. A zero value disables baseline RETREAT strengthening for
## this mob while preserving the shared encounter flow.
@export_range(0, 99, 1) var enhancement_hp_bonus: int = 1


func create_instance() -> MobInstance:
	return MobInstance.new(self)