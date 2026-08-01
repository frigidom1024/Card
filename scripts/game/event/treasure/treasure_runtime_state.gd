class_name TreasureRuntimeState
extends EventRuntimeState

const TreasureRewardOptionScript = preload("res://scripts/game/event/treasure/treasure_reward_option.gd")

var options: Array[TreasureRewardOptionScript] = []
var selected_option_index := -1
