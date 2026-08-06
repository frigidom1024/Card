class_name CardRule
extends Resource


## -1 means this rule can trigger indefinitely. A positive value limits successful
## card-chain applications for each owning CardInstance; 0 disables the rule.
@export_range(-1, 999, 1) var effective_count: int = -1
@export_multiline var description: String


## Resolves this card's combat-time contribution for its own CardResolutionDraft.
## Positional placement rules use execute_on_card_added instead.
func execute(context: CardResolutionContext, draft: CardResolutionDraft) -> CardResolutionDraft:
	return draft


## Resolves after a new card has joined a completed chain. Return true only when
## the rule actually changed the added card, so the chain service can consume one
## effective trigger count for the owning card instance.
func execute_on_card_added(context: CardChainRuleContext) -> bool:
	return false
