class_name CombatCardDeathStateRule
extends CombatStateRule


func evaluate(_effect: CombatBatchEffect, writer: CombatStateWriter) -> CombatValidationResult:
	var cards: Dictionary = writer.get_value(["cards"], {}) as Dictionary
	var chain_ids: Array = writer.get_value(["chain", "card_ids"], []) as Array
	for raw_card_id in cards.keys():
		var card_id := str(raw_card_id)
		if not bool(writer.get_value(["cards", card_id, "alive"], false)):
			continue
		if int(writer.get_value(["cards", card_id, "points"], 0)) > 0:
			continue
		var chain_index := chain_ids.find(card_id)
		var previous_id := ""
		var next_id := ""
		if chain_index > 0:
			previous_id = str(chain_ids[chain_index - 1])
		if chain_index >= 0 and chain_index + 1 < chain_ids.size():
			next_id = str(chain_ids[chain_index + 1])
		writer.set_value(
			["cards", card_id, "alive"],
			false,
			CombatEventTypes.CARD_DIED,
			card_id,
			{
				"card_id": card_id,
				"chain_index_before": chain_index,
				"previous_card_id_before": previous_id,
				"next_card_id_before": next_id,
			}
		)
	return CombatValidationResult.accepted()
