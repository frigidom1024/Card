class_name MobData
extends Resource

@export var mob_name: String = ""
@export var base_stats: CombatStatsData
@export var actions: Array[MobAction] = []
@export var gold_reward: int = 0
@export var card_rewards: Array[CardData] = []


func create_instance() -> MobInstance:
	return MobInstance.new(self)
