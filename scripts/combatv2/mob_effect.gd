class_name MobEffect
extends Resource

## Echo-specific combat hook. It may only edit the pending CombatEffect list.
## The resolver remains the only layer allowed to mutate combat state.
@export var effect_name: String = ""
@export_multiline var description: String = ""
## -1 means unlimited successful hook executions.
@export_range(-1, 999, 1) var effective_count: int = -1

func on_combat_started(draft) -> bool:
	return false


func on_attack(draft) -> bool:
	return false

func on_before_resolve(draft) -> bool:
	return false

func on_card_depleted(draft, card: CardInstance) -> bool:
	return false

