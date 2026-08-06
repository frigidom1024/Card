class_name EncounterRewardResolver
extends RefCounted


## Converts authored encounter drop entries into a reward result without mutating run state.
func resolve(content: EncounterEventContent, rng: RandomNumberGenerator) -> EncounterRewardResult:
	var result := EncounterRewardResult.new()
	if content == null or rng == null:
		return result
	for entry in content.drop_entries:
		if entry == null or not entry.validate().is_empty():
			continue
		if rng.randf() >= entry.chance:
			continue
		match entry.kind:
			EncounterDropEntry.Kind.GOLD:
				result.gold += entry.gold_amount
			EncounterDropEntry.Kind.CARD:
				result.cards.append(entry.card_data)
	return result
