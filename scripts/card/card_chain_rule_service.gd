class_name CardChainRuleService
extends RefCounted

const CardChainRuleContextScript := preload("res://scripts/combatv2/card/card_chain_rule_context.gd")


## Runs all rules currently present in the chain against one newly added card.
## A rule consumes one use only after it returns true, which means that it
## successfully changed the added card.
func resolve_card_added(chain: Array[CardInstance], added_card: CardInstance) -> int:
	if chain.is_empty() or added_card == null or added_card not in chain:
		return 0

	var applied_count := 0
	for source_card in chain:
		if source_card == null or source_card.card_data == null:
			continue
		var rules := source_card.card_data.effect_rules
		for rule_index in range(rules.size()):
			var rule := rules[rule_index]
			if rule == null or not source_card.can_trigger_rule(rule_index, rule.effective_count):
				continue
			var context := CardChainRuleContextScript.new(chain, source_card, added_card)
			if rule.execute_on_card_added(context):
				source_card.record_rule_trigger(rule_index)
				applied_count += 1
	return applied_count
