# Card-Chain Combat Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a pure `CombatService` that resolves one player-versus-one-monster encounter from the ordered card chain, including composable card conditions/effects, root combo rules, monster `next_action()`, combat logs, outcomes, and retreat penalties.

**Architecture:** `CombatService` owns a per-encounter runtime copy of player and monster combat state. Every card starts from its base `damage`/`defense`/`heal`, applies zero or more `CardRule` resources against a pre-card `CardResolutionContext`, then emits executable `CombatEffect` commands. Root cards additionally register runtime `ChainRule` objects; `ChainRuleTracker` decides when the player action batch ends and the monster acts. The service returns `CombatResult` and never mutates the board, UI, event, or caller-owned runtime objects.

**Tech Stack:** Godot 4.7, GDScript, `Resource` for static card rule configuration, `RefCounted` for runtime combat values, the repository's existing `SceneTree`-based test scripts.

## Global Constraints

- One encounter contains exactly one monster and one ordered card chain.
- Player cards resolve automatically; there is no player input during combat.
- Normal flow is one card per player action batch, followed by one monster action.
- Root cards resolve their own effects and register chain rules without triggering a monster action by themselves.
- The demo root rule combines two adjacent `WEAPON` cards into one player action batch; the monster acts once after the pair.
- Card conditions read the combat state captured before the current card resolves.
- Card rules modify only the current card's temporary draft or append effects; they never mutate combatants or future card resources directly.
- `CombatEffect` is the only state-changing command consumed by `CombatService`.
- `MobInstance.next_action()` is the monster action-selection interface; the service must not depend on the selection algorithm.
- Player HP and monster HP persist across encounters according to the existing combat-result contract; armor and ordinary buffs/debuffs are encounter-local.
- `VICTORY` stops immediately without a monster counterattack; `DEFEAT` stops when player HP reaches zero; exhausted cards with both combatants alive produce `RETREAT` and one tail-card removal penalty.
- Do not modify unrelated existing working-tree changes.

---

## File Map

Create these focused runtime/domain files:

- `scripts/combat/combat_effect.gd` — immutable-ish runtime command describing damage, defense, or healing.
- `scripts/combat/combat_step.gd` — one replayable/loggable resolution step.
- `scripts/combat/combat_result.gd` — outcome, final snapshots, steps, penalties, and processed-card count.
- `scripts/combat/combat_penalty.gd` — generic externally-applied encounter consequence.
- `scripts/combat/combat_state.gd` — mutable per-encounter copy used only inside the service.
- `scripts/combat/card_resolution_context.gd` — pre-card read-only query surface.
- `scripts/combat/card_resolution_draft.gd` — temporary base-plus-rule card result.
- `scripts/combat/card_condition.gd` — base condition Resource contract.
- `scripts/combat/card_operation.gd` — base operation Resource contract.
- `scripts/combat/card_rule.gd` — condition/operation composition.
- `scripts/combat/conditions/previous_card_has_tag_condition.gd` — previous resolved card tag check.
- `scripts/combat/conditions/previous_card_has_type_condition.gd` — previous resolved card type check.
- `scripts/combat/conditions/has_resolved_card_with_tag_condition.gd` — history tag check.
- `scripts/combat/conditions/resolved_card_count_condition.gd` — count comparison check.
- `scripts/combat/conditions/player_hp_ratio_condition.gd` — player HP percentage check.
- `scripts/combat/conditions/monster_hp_ratio_condition.gd` — monster HP percentage check.
- `scripts/combat/conditions/is_first_card_condition.gd` — chain-position check.
- `scripts/combat/conditions/is_last_card_condition.gd` — chain-position check.
- `scripts/combat/operations/add_damage_operation.gd` — draft damage increment.
- `scripts/combat/operations/multiply_damage_operation.gd` — draft damage multiplier.
- `scripts/combat/operations/add_defense_operation.gd` — draft defense increment.
- `scripts/combat/operations/add_heal_operation.gd` — draft healing increment.
- `scripts/combat/operations/add_combat_effect_operation.gd` — append an extra effect command.
- `scripts/combat/chain_rule.gd` — runtime root-chain rule state.
- `scripts/combat/root_chain_rule_provider.gd` — base Resource contract for root rule providers.
- `scripts/combat/root_rules/weapon_combo_root_rule_provider.gd` — adjacent matching-tag combo provider.
- `scripts/combat/chain_rule_tracker.gd` — action-batch and combo consumption logic.
- `scripts/combat/mob_action_resolver.gd` — maps `MobAction` to `CombatEffect` commands.
- `scripts/combat/combat_service.gd` — public encounter resolver and orchestration.
- `tests/fixtures/cards/weapon_combo_root.tres` — isolated serialized root-provider compatibility fixture.

Modify these existing files:

- `scripts/card/card_data.gd` — add typed `effect_rules` and root rule provider references while retaining `damage`, `defense`, and `heal`.
- `scripts/combat/combat_stats.gd` — add runtime-copy support without resetting HP to max.
- `scripts/game/event/mob_instance.gd` — expose `next_action()`, create encounter-isolated copies, and preserve `get_next_action()` as a compatibility delegate.
- `tests/combat_model_test.gd` — add assertions for the new `next_action()` contract without removing current model tests.

Create the focused test file:

- `tests/combat_service_test.gd` — headless `SceneTree` tests for card rules, combo timing, monster actions, outcomes, logs, and penalties.

---

### Task 1: Add runtime combat primitives and copy-safe state

**Files:**
- Create: `scripts/combat/combat_effect.gd`
- Create: `scripts/combat/combat_step.gd`
- Create: `scripts/combat/combat_result.gd`
- Create: `scripts/combat/combat_penalty.gd`
- Create: `scripts/combat/combat_state.gd`
- Modify: `scripts/combat/combat_stats.gd`
- Create: `tests/combat_service_test.gd`

**Interfaces:**
- `CombatEffect.new(type: Type, target: Target, value: int, source_type: SourceType, source_name: String = "") -> CombatEffect`
- `CombatStep.new(kind: Kind, source_name: String, effects: Array[CombatEffect], player_before: CombatStats, player_after: CombatStats, monster_before: CombatStats, monster_after: CombatStats) -> CombatStep`
- `CombatResult.new(outcome: Outcome, player_stats_after: CombatStats, monster_stats_after: CombatStats, steps: Array[CombatStep], processed_card_count: int, penalties: Array[CombatPenalty]) -> CombatResult`
- `CombatStats.duplicate_runtime() -> CombatStats`
- `CombatPenalty.new(type: Type, amount: int, target: Target) -> CombatPenalty`
- `CombatState.new(player_stats_copy: CombatStats, monster_copy: MobInstance, cards: Array[CardInstance]) -> CombatState`
- `CombatResult.Outcome` contains `VICTORY`, `RETREAT`, `DEFEAT`.
- `CombatPenalty.Type` contains `REMOVE_CARD`; `CombatPenalty.Target` contains `TAIL_OF_CARD_CHAIN`.

- [ ] **Step 1: Write failing primitive tests**

Add tests that construct a `CombatEffect` and `CombatPenalty`, duplicate `CombatStats` with damaged HP and defense, and verify the duplicate can change without changing the source:

```gdscript
var source := CombatStats.new()
source.max_hp = 20
source.hp = 9
source.defense = 3

var copy := source.duplicate_runtime()
copy.take_damage(5)

_expect(copy.hp != source.hp, "runtime copies can change independently")
_expect(source.hp == 9 and source.defense == 3, "runtime copy does not mutate source stats")

var penalty := CombatPenalty.new(
	CombatPenalty.Type.REMOVE_CARD,
	1,
	CombatPenalty.Target.TAIL_OF_CARD_CHAIN
)
_expect(penalty.amount == 1, "retreat penalty carries its amount")
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
```

Expected: FAIL because the new runtime classes and copy method do not exist.

- [ ] **Step 3: Implement the primitives**

Use `RefCounted` for runtime objects. Keep `CombatEffect` as a data command with enums for:

```gdscript
enum Type { DAMAGE, ADD_DEFENSE, HEAL }
enum Target { PLAYER, MONSTER }
enum SourceType { PLAYER_CARD, ROOT_CARD, MONSTER_ACTION, SYSTEM }
```

`CombatStep.Kind` contains `ROOT_CARD`, `PLAYER_CARD`, and `MONSTER_ACTION`. Its constructor duplicates every before/after `CombatStats` snapshot and duplicates the effects array so later state changes cannot rewrite the log. `CombatResult` likewise owns duplicated final stats, steps, and penalties; `processed_card_count` includes the root because its effects are actually resolved.

`CombatStats.duplicate_runtime()` must copy `max_hp`, `hp`, `attack`, and `defense` exactly, rather than calling `reset_from_data()`.

`CombatPenalty` is a `RefCounted` value object. Clamp `amount` to zero or greater; the service only creates `REMOVE_CARD` targeting `TAIL_OF_CARD_CHAIN` in the demo.

`CombatState` must store the already-isolated player stats, the encounter-local `MobInstance`, an ordered duplicate of the card array, `resolved_cards`, `remaining_cards`, and `steps`. It must not retain the caller-owned monster instance. Do not add `ChainRule`-typed fields yet; Task 3 adds them after that class exists.

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
```

Expected: PASS for the primitive tests.

- [ ] **Step 5: Commit**

```text
git add scripts/combat/combat_effect.gd scripts/combat/combat_step.gd scripts/combat/combat_result.gd scripts/combat/combat_penalty.gd scripts/combat/combat_state.gd scripts/combat/combat_stats.gd tests/combat_service_test.gd
git commit -m "feat: add combat runtime primitives"
```

### Task 2: Add card context, draft, rules, conditions, and operations

**Files:**
- Create: `scripts/combat/card_resolution_context.gd`
- Create: `scripts/combat/card_resolution_draft.gd`
- Create: `scripts/combat/card_condition.gd`
- Create: `scripts/combat/card_operation.gd`
- Create: `scripts/combat/card_rule.gd`
- Create: `scripts/combat/conditions/previous_card_has_tag_condition.gd`
- Create: `scripts/combat/conditions/previous_card_has_type_condition.gd`
- Create: `scripts/combat/conditions/has_resolved_card_with_tag_condition.gd`
- Create: `scripts/combat/conditions/resolved_card_count_condition.gd`
- Create: `scripts/combat/conditions/player_hp_ratio_condition.gd`
- Create: `scripts/combat/conditions/monster_hp_ratio_condition.gd`
- Create: `scripts/combat/conditions/is_first_card_condition.gd`
- Create: `scripts/combat/conditions/is_last_card_condition.gd`
- Create: `scripts/combat/operations/add_damage_operation.gd`
- Create: `scripts/combat/operations/multiply_damage_operation.gd`
- Create: `scripts/combat/operations/add_defense_operation.gd`
- Create: `scripts/combat/operations/add_heal_operation.gd`
- Create: `scripts/combat/operations/add_combat_effect_operation.gd`
- Modify: `scripts/card/card_data.gd`
- Modify: `tests/combat_service_test.gd`

**Interfaces:**
- `CardCondition.evaluate(context: CardResolutionContext) -> bool`
- `CardCondition.compare_values(actual: float, expected: float, comparison: Comparison) -> bool`
- `CardOperation.apply(context: CardResolutionContext, draft: CardResolutionDraft) -> void`
- `CardRule.apply(context: CardResolutionContext, draft: CardResolutionDraft) -> void`
- `CardResolutionDraft.from_card(card: CardData) -> CardResolutionDraft`
- `CardResolutionDraft.to_effects(source_type: CombatEffect.SourceType, source_name: String) -> Array[CombatEffect]`
- `CardResolutionContext.new(state: CombatState, current_card: CardInstance, current_index: int) -> CardResolutionContext`

- [ ] **Step 1: Write failing condition and operation tests**

Add tests for a card with `damage = 5`, a previous `WEAPON` card, and one `CardRule` combining `PreviousCardHasTagCondition(WEAPON)` with `MultiplyDamageOperation(2)`. Add a separate assertion for `PreviousCardHasTypeCondition(CardData.CardType.ROOT)`. Also verify that a low-HP condition adds healing and that the first/last-card conditions use the full chain position.

```gdscript
var draft := CardResolutionDraft.from_card(current_card.card_data)
var context := CardResolutionContext.new(state, current_card, 1)
rule.apply(context, draft)
var effects := draft.to_effects(CombatEffect.SourceType.PLAYER_CARD, "Test Card")

_expect(effects.size() == 1, "damage-only draft emits one effect")
_expect(effects[0].value == 10, "previous weapon rule doubles current damage")
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
```

Expected: FAIL because the condition, operation, draft, and card-rule contracts are not implemented.

- [ ] **Step 3: Implement the context and draft**

`CardResolutionContext` must expose read-only query methods for the current card, previous resolved card, resolved cards, remaining cards, player/monster HP and defense, and first/last position. Its constructor copies those readable values from the pre-card state so every rule sees the same snapshot even if a custom rule retains the context; it must not expose mutators. Task 3 extends the context with chain-rule IDs and current-batch scalars after the chain types exist.

`CardResolutionDraft` must initialize from the current card's `damage`, `defense`, and `heal`, hold `extra_effects`, and emit only positive base values. Negative additions must clamp at zero. `to_effects()` emits base effects in deterministic `DAMAGE(MONSTER)`, `ADD_DEFENSE(PLAYER)`, `HEAL(PLAYER)` order, then appends `extra_effects` in operation order. All conditions must read the same context snapshot before any effects from the current card are applied.

- [ ] **Step 4: Implement the condition and operation Resources**

Use `Resource` subclasses with exported parameters. Implement `PreviousCardHasTagCondition`, `PreviousCardHasTypeCondition`, `HasResolvedCardWithTagCondition`, `ResolvedCardCountCondition`, `PlayerHpRatioCondition`, `MonsterHpRatioCondition`, `IsFirstCardCondition`, and `IsLastCardCondition`. Define `CardCondition.Comparison` as `EQUAL`, `GREATER_THAN`, `GREATER_OR_EQUAL`, `LESS_THAN`, and `LESS_OR_EQUAL`; `ResolvedCardCountCondition`, `PlayerHpRatioCondition`, and `MonsterHpRatioCondition` use the shared comparator. Ratio thresholds are exported floats clamped to `0.0..1.0`. Previous-tag/type and resolved-history conditions export their required tag/type. Add/multiply operations export their numeric amount or multiplier; `AddCombatEffectOperation` exports effect type, target, and value. `CardRule.apply()` must run the operation only when its condition is absent or evaluates true. Keep `apply()` overridable so a future custom `CardRule` can implement complex behavior while still receiving only the snapshot context and current draft.

- [ ] **Step 5: Add `CardData` exports without removing existing fields**

Add only the card-level rule export in this task:

```gdscript
@export var effect_rules: Array[CardRule] = []
```

Keep `damage`, `defense`, `heal`, `card_type`, and tags unchanged so existing `.tres` card resources remain loadable. Task 3 adds the root provider export after `RootChainRuleProvider` exists.

- [ ] **Step 6: Run the focused tests and verify they pass**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
```

Expected: PASS for base draft creation, previous-tag multiplication, HP conditions, count conditions, first/last position, and extra-effect emission.

- [ ] **Step 7: Commit**

```text
git add scripts/combat/card_resolution_context.gd scripts/combat/card_resolution_draft.gd scripts/combat/card_condition.gd scripts/combat/card_operation.gd scripts/combat/card_rule.gd scripts/combat/conditions scripts/combat/operations scripts/card/card_data.gd tests/combat_service_test.gd
git commit -m "feat: add composable card effect rules"
```

### Task 3: Add root chain rules and action-batch tracking

**Files:**
- Create: `scripts/combat/chain_rule.gd`
- Create: `scripts/combat/root_chain_rule_provider.gd`
- Create: `scripts/combat/root_rules/weapon_combo_root_rule_provider.gd`
- Create: `scripts/combat/chain_rule_tracker.gd`
- Modify: `scripts/combat/combat_state.gd`
- Modify: `scripts/combat/card_resolution_context.gd`
- Modify: `scripts/card/card_data.gd`
- Modify: `tests/combat_service_test.gd`

**Interfaces:**
- `RootChainRuleProvider.build_rules(context: CardResolutionContext) -> Array[ChainRule]`
- `ChainRule.new(rule_id: StringName, required_tag: CardData.CardTag, matching_count: int, source_name: String) -> ChainRule`
- `ChainRuleTracker.start(rules: Array[ChainRule]) -> void`
- `ChainRuleTracker.begin_card(card: CardInstance) -> bool`
- `ChainRuleTracker.finish_card(card: CardInstance) -> bool`
- `ChainRuleTracker.flush_pending() -> bool`

- [ ] **Step 1: Write failing combo tests**

Add tests for these exact chains:

```text
ROOT -> WEAPON -> WEAPON -> HEAL
```

Expected monster action timing:

```text
after WEAPON + WEAPON batch
and after HEAL
```

Also test:

```text
ROOT -> WEAPON -> HEAL -> WEAPON
```

Expected: `begin_card(HEAL)` first closes the pending single-weapon batch and requests a monster action; `finish_card(HEAL)` requests another action; the final weapon remains pending until `flush_pending()` requests its action. The two non-adjacent weapons never combo. Add `ROOT -> WEAPON` as a focused end-of-chain flush case.

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
```

Expected: FAIL because chain-rule runtime and batch tracking do not exist.

- [ ] **Step 3: Implement `ChainRule` and the provider contract**

`ChainRule` is a per-encounter runtime object with `rule_id`, required tag, remaining matching cards, source card name, and an open-batch flag. `RootChainRuleProvider` is a stateless `Resource` contract.

`WeaponComboRootRuleProvider` must export `required_tag = WEAPON` and `matching_count = 2`, and return a runtime `ChainRule` from `build_rules()`. Extend `CombatState` with `active_chain_rules: Array[ChainRule]`, `current_batch_id`, and `current_batch_card_count`; extend `CardResolutionContext` with copied chain-rule IDs and current-batch scalars, without returning mutable runtime rule objects. After these classes exist, add the typed export to `CardData`:

```gdscript
@export var root_rule_providers: Array[RootChainRuleProvider] = []
```

- [ ] **Step 4: Implement `ChainRuleTracker`**

The tracker must enforce adjacency with explicit return values:

```text
begin_card(card) -> true when a previously open, incomplete batch must receive its monster action before this card
finish_card(card) -> true when the current card completes an ordinary or matched batch
flush_pending() -> true when the chain ended with an open, incomplete batch
```

The first matching card opens a batch and makes `finish_card()` return false. The second adjacent matching card closes the batch and makes `finish_card()` return true. A nonmatching card makes `begin_card()` close the pending combo and return true; after that card resolves, its own `finish_card()` also returns true. At end of chain, `flush_pending()` closes a lone matching card so it still receives a monster action before `RETREAT`.

When the tracker has no active combo rule, every card's `begin_card()` returns false and `finish_card()` returns true. If multiple root rules are present in data, the demo tracker must keep only the first rule of the same rule type and not stack identical combo rules.

- [ ] **Step 5: Run combo tests and verify they pass**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
```

Expected: PASS for adjacent two-card combo, non-adjacent non-combo, no extra monster action between combo cards, and end-of-chain pending-batch flush.

- [ ] **Step 6: Commit**

```text
git add scripts/combat/chain_rule.gd scripts/combat/root_chain_rule_provider.gd scripts/combat/root_rules/weapon_combo_root_rule_provider.gd scripts/combat/chain_rule_tracker.gd scripts/combat/combat_state.gd scripts/combat/card_resolution_context.gd scripts/card/card_data.gd tests/combat_service_test.gd
git commit -m "feat: add root chain action batches"
```

### Task 4: Add monster action adapter and `next_action()` contract

**Files:**
- Create: `scripts/combat/mob_action_resolver.gd`
- Modify: `scripts/game/event/mob_instance.gd`
- Modify: `tests/combat_model_test.gd`
- Modify: `tests/combat_service_test.gd`

**Interfaces:**
- `MobInstance.next_action() -> MobAction`
- `MobInstance.duplicate_for_encounter() -> MobInstance`
- `MobActionResolver.to_effects(action: MobAction, source_name: String) -> Array[CombatEffect]`

- [ ] **Step 1: Write failing action-interface tests**

Add an assertion that `mob.next_action()` returns the first configured action and the next call returns the next configured action. Set a source mob's current HP below max and its `action_index` to a nonzero value, then assert that `duplicate_for_encounter()` preserves the current stats in an independent `CombatStats`, references the same immutable `MobData`, and resets `action_index` to `0`. Add adapter tests:

```gdscript
var attack := MobAction.new()
attack.type = MobAction.Type.ATTACK
attack.value = 4
var effects := MobActionResolver.to_effects(attack, "Test Mob")
_expect(effects.size() == 1, "attack action emits one effect")
_expect(effects[0].type == CombatEffect.Type.DAMAGE, "attack maps to damage")
_expect(effects[0].target == CombatEffect.Target.PLAYER, "attack targets player")
```

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
godot --headless --path . --script tests/combat_model_test.gd
```

Expected: the new `next_action()` and adapter assertions fail.

- [ ] **Step 3: Implement `MobInstance.next_action()`**

Move the action selection body into `next_action()`. Keep `get_next_action()` as:

```gdscript
func get_next_action() -> MobAction:
    return next_action()
```

This preserves existing callers while making `next_action()` the service-facing contract. Add:

```gdscript
func duplicate_for_encounter() -> MobInstance:
	var copy := MobInstance.new(data)
	copy.stats = stats.duplicate_runtime() if stats else null
	copy.action_index = 0
	return copy
```

The copy keeps the monster's current HP for a retry, starts the demo action list from its first entry, and prevents the service from advancing the caller-owned `action_index`.

- [ ] **Step 4: Implement `MobActionResolver`**

Map `ATTACK`, `DEFEND`, and `HEAL` to `DAMAGE`, `ADD_DEFENSE`, and `HEAL`. Use `MobAction.value` directly, clamp negative values to zero through the effect constructor, and return an empty array for `BUFF`, `DEBUFF`, and `SPECIAL` in the demo while preserving their enum values for future expansion.

- [ ] **Step 5: Run both tests and verify they pass**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
godot --headless --path . --script tests/combat_model_test.gd
```

Expected: PASS with existing combat model tests unchanged.

- [ ] **Step 6: Commit**

```text
git add scripts/combat/mob_action_resolver.gd scripts/game/event/mob_instance.gd tests/combat_model_test.gd tests/combat_service_test.gd
git commit -m "feat: expose monster next action resolver"
```

### Task 5: Implement pure `CombatService` orchestration

**Files:**
- Create: `scripts/combat/combat_service.gd`
- Modify: `scripts/combat/combat_state.gd`
- Modify: `scripts/combat/combat_result.gd`
- Modify: `scripts/combat/combat_step.gd`
- Modify: `tests/combat_service_test.gd`

**Interfaces:**
- `CombatService.resolve_encounter(player_stats: CombatStats, card_chain: Array[CardInstance], monster: MobInstance) -> CombatResult`
- `CombatService.apply_effect(state: CombatState, effect: CombatEffect) -> int` — returns actual HP damage, defense gained, or HP healed.
- `CombatService.resolve_player_card(state: CombatState, card: CardInstance, index: int, source_type: CombatEffect.SourceType) -> bool` — returns true only when the monster dies.
- `CombatService.resolve_monster_action(state: CombatState) -> bool` — returns true only when the player dies.

- [ ] **Step 1: Write failing end-to-end service tests**

Cover these exact scenarios:

```text
1. One attack card reduces monster HP and then causes one monster action.
2. A lethal card returns VICTORY and does not call the monster action.
3. A root resolves its own defense, registers its rule, and does not call the monster action.
4. Two adjacent weapons under the root combo receive one monster action after the pair.
5. A non-adjacent weapon sequence receives one monster action per card.
6. A low-HP conditional card emits its extra heal using pre-card HP.
7. Exhausted cards with both actors alive return RETREAT and one tail-card penalty.
8. A monster attack that reaches zero player HP returns DEFEAT immediately.
9. `CombatResult.steps` contains ordered root, player-card, and monster-action entries with immutable before/after snapshots.
10. The input monster's `action_index`, HP, and defense remain unchanged after resolution.
11. `ROOT -> WEAPON` flushes the incomplete batch, gives the monster one action, and only then returns RETREAT if the player survives.
```

Example assertion shape:

```gdscript
var result := CombatService.new().resolve_encounter(player_stats, cards, mob)
_expect(result.outcome == CombatResult.Outcome.VICTORY, "lethal card wins")
_expect(result.steps.size() == 1, "lethal card has no monster response step")
_expect(result.player_stats_after.hp == player_stats.hp, "service does not mutate input player stats")
```

- [ ] **Step 2: Run the service tests and verify they fail**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
```

Expected: FAIL because `CombatService` is not defined.

- [ ] **Step 3: Implement service initialization and copy isolation**

`resolve_encounter()` must:

```text
player_stats.duplicate_runtime()
monster.duplicate_for_encounter()
copy card order without duplicating immutable CardData resources
create CombatState from those isolated runtime objects
```

The input `CombatStats`, `MobInstance`, and `CardInstance` objects must remain unchanged. The returned `CombatResult` must own the final runtime snapshots.

- [ ] **Step 4: Implement root resolution**

Require the first card to be the root for the demo. Resolve its base effects and `effect_rules`, append one `ROOT_CARD` step, append the root to `resolved_cards`, and increment `processed_card_count`. If the root kills the monster, return `VICTORY` immediately. Otherwise call every configured root provider to build runtime chain rules. Do not call `next_action()` after the root.

- [ ] **Step 5: Implement player-card resolution**

For each remaining card:

```text
create pre-card context
create draft from card data
apply card rules in array order
convert draft to effects
apply effects in returned order
append a PLAYER_CARD step
append card to resolved history
```

After every effect and every monster action, check terminal HP state. If the monster dies, return `VICTORY` immediately; if the player dies, return `DEFEAT` immediately.

- [ ] **Step 6: Implement action-batch and monster-action timing**

Call `ChainRuleTracker.begin_card()` before resolving each non-root card. If it returns true, resolve one monster action before the current card and stop immediately on `DEFEAT`. After the card resolves, call `finish_card()`; if it returns true, resolve one monster action unless the card already produced `VICTORY`. After all cards are consumed, call `flush_pending()` and resolve its requested monster action before deciding `RETREAT`.

Every monster turn must call `state.monster.next_action()` on the encounter-local copy, convert the action with `MobActionResolver`, apply its effects, and append one `MONSTER_ACTION` step. Never call `next_action()` on the input `monster`. A null action produces an empty-effect step and does not crash the encounter.

- [ ] **Step 7: Implement result and penalty construction**

When all cards are consumed while both actors are alive, return:

```text
outcome = RETREAT
penalties = [CombatPenalty.new(REMOVE_CARD, 1, TAIL_OF_CARD_CHAIN)]
```

For `VICTORY`, return no retreat penalty. For `DEFEAT`, return the final player state and stop without attempting to continue the chain.

- [ ] **Step 8: Run all service tests and verify they pass**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
godot --headless --path . --script tests/combat_model_test.gd
```

Expected: PASS for all combat service and existing model coverage.

- [ ] **Step 9: Commit**

```text
git add scripts/combat/combat_service.gd scripts/combat/combat_state.gd scripts/combat/combat_result.gd scripts/combat/combat_penalty.gd scripts/combat/combat_step.gd tests/combat_service_test.gd
git commit -m "feat: resolve card chain combat encounters"
```

### Task 6: Add serialized fixture and regression coverage for current resources

**Files:**
- Create: `tests/fixtures/cards/weapon_combo_root.tres`
- Modify: `tests/combat_service_test.gd`

**Interfaces:**
- Existing `.tres` files must load through the unchanged `CardData` fields.
- New rule resources must be assignable through typed `CardData.effect_rules` and `CardData.root_rule_providers` exports.

- [ ] **Step 1: Add a failing resource-load regression test**

Verify that all existing card resources still load and that cards without `effect_rules` use only their base fields. Verify a dedicated root fixture loads with one weapon-combo provider.

```gdscript
for file_name in DirAccess.get_files_at("res://data/cards"):
	if file_name.ends_with(".tres"):
		var card := load("res://data/cards/%s" % file_name) as CardData
		_expect(card != null, "existing card loads: %s" % file_name)

var legacy := load("res://data/cards/AllThingsRevival.tres") as CardData
_expect(legacy.effect_rules.is_empty(), "legacy card defaults to no rules")
_expect(CardResolutionDraft.from_card(legacy).heal == legacy.heal, "legacy base heal is preserved")

var root := load("res://tests/fixtures/cards/weapon_combo_root.tres") as CardData
_expect(root != null, "combo root fixture loads")
_expect(root.root_rule_providers.size() == 1, "combo root has one provider")
```

- [ ] **Step 2: Run the regression test and verify it fails**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
```

Expected: FAIL until the fixture and typed Resource exports are configured.

- [ ] **Step 3: Create the isolated root fixture**

Create `tests/fixtures/cards/weapon_combo_root.tres` with a `CardData` root and one inline `WeaponComboRootRuleProvider`; do not modify production cards:

```text
[gd_resource type="Resource" script_class="CardData" format=3]

[ext_resource type="Script" path="res://scripts/card/card_data.gd" id="1_card"]
[ext_resource type="Script" path="res://scripts/combat/root_rules/weapon_combo_root_rule_provider.gd" id="2_provider"]

[sub_resource type="Resource" id="WeaponComboProvider_test"]
script = ExtResource("2_provider")
required_tag = 0
matching_count = 2

[resource]
script = ExtResource("1_card")
card_id = -1
card_name = "Test Weapon Combo Root"
card_type = 0
root_rule_providers = Array[ExtResource("2_provider")]([SubResource("WeaponComboProvider_test")])
```

`required_tag = 0` is `CardData.CardTag.WEAPON`; keep this fixture under `tests/fixtures` so combat-service work does not rebalance `PlayerRoot.tres` or any production card.

- [ ] **Step 4: Run all tests and verify they pass**

Run:

```text
godot --headless --path . --script tests/combat_service_test.gd
godot --headless --path . --script tests/combat_model_test.gd
```

Expected: PASS with all existing resources loading and the new fixture resolving correctly.

- [ ] **Step 5: Commit**

```text
git add tests/fixtures/cards/weapon_combo_root.tres tests/combat_service_test.gd
git commit -m "test: cover combat card resource fixtures"
```

### Task 7: Verify the complete implementation boundary

**Files:**
- Modify: `docs/superpowers/specs/2026-07-31-card-chain-combat-design.md` only if implementation reveals a confirmed behavior correction.
- Modify: `tests/combat_service_test.gd` only for a missing contract regression.

**Interfaces:**
- No new public interface. This task verifies the exact `CombatService.resolve_encounter()` contract and the result data consumed by future event/UI integration.

- [ ] **Step 1: Run the complete existing and new test scripts**

Run:

```text
godot --headless --path . --script tests/combat_model_test.gd
godot --headless --path . --script tests/combat_service_test.gd
```

Expected: both exit with code `0` and no unexpected parser/runtime errors.

- [ ] **Step 2: Review the diff for scope isolation**

Run:

```text
git diff c35228c..HEAD -- scripts/card scripts/combat scripts/game/event/mob_instance.gd tests data/cards
```

Confirm that the implementation does not modify board rendering, event UI, reward application, penalty application, or game-manager flow.

- [ ] **Step 3: Commit any verified documentation correction separately**

```text
git add docs/superpowers/specs/2026-07-31-card-chain-combat-design.md tests/combat_service_test.gd
git commit -m "docs: align combat service contract with implementation"
```

---

## Execution Notes

- The current working tree contains unrelated resource, scene, script, and temporary-log changes. Each implementation task must stage only the files listed for that task.
- The repository currently has `tests/combat_model_test.gd` as a `SceneTree` self-check script rather than a unit-test framework. Keep the same style for `tests/combat_service_test.gd` so it can run headlessly without adding dependencies.
- Existing `CombatStats.take_damage()` already consumes encounter-local defense before HP; reuse that behavior instead of duplicating damage arithmetic in the service.
- `CombatService` must not use `PlayerData.attack` or `CombatStats.attack` for card damage in this first implementation.
- `CombatResult` may expose encounter-end defense for logs, but event integration must persist only player/monster HP after the encounter; ordinary defense and future buffs/debuffs are cleared instead of copied into the next encounter input.
- If the Godot executable is not on `PATH`, run the same commands with the configured Godot 4.7 editor executable; do not install a new test framework for this feature.
