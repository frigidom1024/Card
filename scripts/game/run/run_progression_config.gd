class_name RunProgressionConfig
extends Resource

## Per-run pacing for quality availability. Every stage starts at its configured
## action count; action count measures successful ordinary card placements.
@export var stage_action_thresholds: Array[int] = [0, 4, 8, 12]
@export var rarity_weights_by_stage: Array[Dictionary] = [
    {
        CardData.Rarity.COMMON: 100,
        CardData.Rarity.RARE: 0,
        CardData.Rarity.EPIC: 0,
        CardData.Rarity.LEGENDARY: 0,
    },
    {
        CardData.Rarity.COMMON: 80,
        CardData.Rarity.RARE: 20,
        CardData.Rarity.EPIC: 0,
        CardData.Rarity.LEGENDARY: 0,
    },
    {
        CardData.Rarity.COMMON: 60,
        CardData.Rarity.RARE: 30,
        CardData.Rarity.EPIC: 10,
        CardData.Rarity.LEGENDARY: 0,
    },
    {
        CardData.Rarity.COMMON: 45,
        CardData.Rarity.RARE: 35,
        CardData.Rarity.EPIC: 15,
        CardData.Rarity.LEGENDARY: 5,
    },
]


func validate() -> String:
    if stage_action_thresholds.is_empty():
        return "Progression requires at least one action threshold"
    if rarity_weights_by_stage.size() != stage_action_thresholds.size():
        return "Progression thresholds and rarity weight stages must have equal size"
    var previous_threshold := -1
    for index in stage_action_thresholds.size():
        var threshold := stage_action_thresholds[index]
        if threshold < 0 or threshold <= previous_threshold:
            return "Progression action thresholds must be non-negative and strictly increasing"
        previous_threshold = threshold
        var weights := rarity_weights_by_stage[index]
        var total_weight := 0
        for rarity in CardData.Rarity.values():
            var weight = weights.get(rarity, 0)
            if not (weight is int) or int(weight) < 0:
                return "Progression rarity weights must be non-negative integers"
            total_weight += int(weight)
        if total_weight <= 0:
            return "Every progression stage needs a positive total card weight"
    return ""


func get_stage_index(action_count: int) -> int:
    var stage_index := 0
    for index in stage_action_thresholds.size():
        if action_count >= stage_action_thresholds[index]:
            stage_index = index
        else:
            break
    return stage_index


func get_rarity_weight(rarity: CardData.Rarity, action_count: int) -> int:
    if rarity_weights_by_stage.is_empty():
        return 0
    var stage_index := mini(get_stage_index(action_count), rarity_weights_by_stage.size() - 1)
    return maxi(0, int(rarity_weights_by_stage[stage_index].get(rarity, 0)))
