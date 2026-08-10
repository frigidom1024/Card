class_name CardRule
extends Resource


## -1 means this rule can trigger indefinitely. A positive value limits successful
## card-chain applications for each owning CardInstance; 0 disables the rule.
@export_range(-1, 999, 1) var effective_count: int = -1
@export_multiline var description: String


## Placement-time rule hook.
func execute_on_card_added(context: CardChainRuleContext) -> bool:
	return false


## Returns true when this card should resolve once before the chain head.
func should_trigger_before_head(context: CardResolutionContext) -> bool:
	return false


## Pre-combat positional hooks run before the ordinary head-to-root clashes.
## The rule may add one-way effects to the draft without implicitly creating a
## monster retaliation effect. CombatService2 still resolves the draft through
## CombatEffectResolver so logs and animation consumers see the same payload.
func on_pre_combat(draft) -> bool:
	return false


## Combat hooks return true only if the rule changed the shared effect draft.
## CombatService2 uses that result to consume effective_count on the owning card.
## Rules must never mutate card, player, or monster state directly.
func on_combat_started(draft) -> bool:
	return false


func on_attack(draft) -> bool:
	return false


func on_before_resolve(draft) -> bool:
	return false


func on_card_depleted(draft, card: CardInstance) -> bool:
	return false
