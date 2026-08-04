class_name PlayerData
extends Resource

const INITIAL_FAITH := 3

@export var player_name: String = "Player"
@export var base_stats: CombatStatsData
@export var gold: int = 30
# Run-scoped belief resource. GameManager resets it after duplicating this data for a new run.
@export var faith: int = INITIAL_FAITH
