# Encounter Combat Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route board-triggered `MONSTER` and `BOSS` events through the default automatic combat service and apply their outcomes back to the exploration state.

**Architecture:** `Board` remains responsible only for emitting `event_triggered` after a legal card placement overlaps one unresolved event. `GameManager` owns exploration interaction state and result application. A small `CombatServiceRouter` selects the default `CombatService2` now, while an `EncounterCombatFlowCoordinator` begins an encounter and invokes that router; later, Root-card-specific combat services can be selected inside the router without changing event or UI flow.

**Tech Stack:** Godot 4.7, GDScript, SceneTree headless integration tests.

## Global Constraints

- Only `EventData.EventType.MONSTER` and `EventData.EventType.BOSS` enter the combat route in this task.
- `SHOP` and `TREASURE` must remain unresolved and must not emit combat signals when overlapped.
- `CombatService2` remains a pure calculator; it must not access the board, UI, or event display.
- `GameManager` applies permanent results: victory resolves the event, retreat preserves only monster HP and removes the tail card, defeat persists player HP at zero and ends exploration.
- Encounter-only defenses are cleared after every outcome; the player's HP is not written back on retreat.
- Preserve all pre-existing, uncommitted event-script reference changes.

---

### Task 1: Define routing behavior with a real GameManager scene test

**Files:**
- Create: `tests/game_manager_combat_routing_test.gd`

- [ ] Verify a board-triggered monster victory resolves the event, emits combat lifecycle signals, and restores interaction.
- [ ] Verify retreat retains monster HP, restores the pre-encounter player HP, clears temporary defense, and removes the actual last board card.
- [ ] Verify defeat writes player HP zero, emits exploration failure, leaves interaction locked, and does not resolve the event.
- [ ] Verify a shop event is ignored by the combat route.

### Task 2: Add focused encounter routing collaborators

**Files:**
- Create: `scripts/game/event/encounter/combat_service_router.gd`
- Create: `scripts/game/event/encounter/encounter_combat_flow_coordinator.gd`

- [ ] `CombatServiceRouter.resolve(player_stats, card_chain, monster)` delegates to `CombatService2`.
- [ ] `EncounterCombatFlowCoordinator.resolve(instance, player_stats, card_chain)` begins a Monster/Boss encounter and returns both the runtime monster and `CombatResult`; invalid event types return no resolution.

### Task 3: Connect GameManager to Board and apply outcomes

**Files:**
- Modify: `scripts/game_manager.gd`
- Modify: `scripts/game/board.gd`
- Modify: `scripts/game/event.gd`

- [ ] Board exposes the ordered card-chain snapshot consumed by combat.
- [ ] GameManager subscribes to `Board.event_triggered`, locks interaction while resolving, and emits `combat_started`, `combat_resolved`, and `exploration_failed` signals.
- [ ] Victory resolves and refreshes the event display.
- [ ] Retreat writes only monster HP, resets encounter defense, applies the tail-card penalty through board/card ownership, and unlocks interaction.
- [ ] Defeat writes player HP, clears transient defenses, keeps interaction locked, and emits failure.

### Task 4: Verify the route and existing regressions

**Files:**
- Test: `tests/game_manager_combat_routing_test.gd`
- Test: `tests/event_runtime_test.gd`
- Test: `tests/event_trigger_test.gd`
- Test: `tests/combatv2_card_rule_test.gd`
- Test: `tests/combatv2_service_test.gd`

- [ ] Run the new routing integration test.
- [ ] Run all existing event and Combat V2 test scripts headlessly.
- [ ] Run `git diff --check` and inspect `git diff --stat` to confirm no unrelated files were altered.