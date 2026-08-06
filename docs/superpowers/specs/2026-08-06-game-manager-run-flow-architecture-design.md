# GameManager Run-Flow Architecture Refactor Design

**Date:** 2026-08-06  
**Status:** Approved approach B — awaiting written-spec review  
**Scope:** Runtime architecture only; card balance, Ribwood content, EventLib data, battle rules, and UI layout visuals are out of scope.

## 1. Goal

Make `GameManager` a scene composition root instead of a cross-domain controller. The refactor must make placement ordering, event interaction, combat settlement, run lifecycle, runtime data ownership, and UI synchronization explicit and testable.

The system must preserve these gameplay contracts:

- `Board.placement_committed` represents one completed spatial placement.
- Card rules execute before exploration reacts to that placement.
- Bosses remain ordinary `BOSS` events. Boss pursuit only changes the Boss event location; card contact uses the same event → combat → settlement path as every other encounter.
- Boss pursuit remains configurable through `ExplorationConfig`.
- Faith retraction still requests a normal exploration encounter at faith <= 0.
- A combat RETREAT keeps its existing penalty contract.
- Victory, defeat, retreat, shop, treasure, guide-card return, persistent market, and existing Ribwood resources continue to use their current gameplay rules.

## 2. Current Failure and Architectural Problems

### 2.1 Blocking callback regression

`GameManager._configure_exploration()` connects `Board.placement_committed` to `_on_board_placement_committed`, but that method no longer exists. The current project therefore fails to parse `scripts/game_manager.gd` after a fresh Godot class scan.

This must be removed as part of replacing direct Board callback wiring with one explicit placement pipeline.

### 2.2 Implicit placement ordering

`CardChainCoordinator` and GameManager's exploration callback both subscribe to `Board.placement_committed`. Current ordering depends on connection order in `_ready()`, which is an undocumented gameplay dependency.

### 2.3 Scattered lifecycle and failure state

`GameManager._is_exploration_failed`, EventModal interaction state, pending combat state, and DragLayer locking together represent run state. No single owner can atomically transition between exploring, interacting, failed, and finished states.

### 2.4 Stale runtime references

Player state is copied for a run, but FaithService, EventModalCoordinator, PersistentMarketCoordinator, and EncounterResolutionCoordinator each retain their own references. Replacing runtime state only reconfigures encounter settlement today, so future restart/load/debug flows can diverge.

### 2.5 Two-phase combat settlement can deadlock

The modal hides combat UI before emitting settlement confirmation. If result application fails, the pending interaction remains active while the UI is hidden and exploration stays locked.

### 2.6 GameManager owns presentation and domain flow

GameManager currently forwards HUD, hand count, interaction lock, faith retraction, event start, combat confirmation, layout, and domain state transitions. It remains a high-churn conflict point.

## 3. Chosen Architecture

```text
GameManager (scene composition root)
├── RunSetupCoordinator
│   └── creates RunContext
├── RunFlowCoordinator
│   ├── PlacementPipelineCoordinator
│   │   ├── CardChainCoordinator
│   │   └── ExplorationCoordinator
│   ├── EventModalCoordinator
│   ├── EncounterResolutionCoordinator
│   └── FaithService
├── RunPresentationCoordinator
│   ├── DragLayer lock adapter
│   ├── PilgrimCrestHud adapter
│   └── HandTray adapter
└── PersistentMarketCoordinator
```

`GameManager` may construct these objects and pass scene dependencies, but it must not decide placement phases, apply combat results, invoke exploration placement resolution, mutate run state, or synchronize individual HUD widgets.

## 4. Components and Responsibilities

### 4.1 RunContext

**New file:** `scripts/game/run/run_context.gd`

A run-scoped `RefCounted` object that owns stable references to mutable run state:

```gdscript
var player_data: PlayerData
var player_stats: CombatStats
var card_service: RunCardService
var event_interaction_controller: EventInteractionController
var random: RunRandomService
```

`RunSetupCoordinator` creates the runtime player copy, combat stats, card service, combat flow, and interaction controller, then exposes one configured `RunContext`.

Compatibility getters may remain temporarily in RunSetupCoordinator, but GameManager and all newly refactored coordinators use `RunContext`.

**Invariant:** Runtime player state is never replaced by assigning `GameManager.player_data` or `player_stats`. A future restart/load operation creates a new RunContext and reconfigures the run flow as one lifecycle operation.

### 4.2 RunRandomService

**New file:** `scripts/game/run/run_random_service.gd`

Provides seeded, independent random streams:

```gdscript
func market_rng() -> RandomNumberGenerator
func treasure_rng() -> RandomNumberGenerator
func encounter_reward_rng() -> RandomNumberGenerator
```

A seed can be supplied for deterministic tests/replays; production defaults to randomization once per run. Event modal and market must receive streams from RunContext rather than calling `randomize()` themselves.

### 4.3 PlacementPipelineCoordinator

**New file:** `scripts/game/placement/placement_pipeline_coordinator.gd`

This is the **only** subscriber to `Board.placement_committed` for run gameplay.

On every placement it executes the fixed pipeline:

```text
1. Reject when the run is not EXPLORING.
2. Resolve card-chain rules for CHAIN_EXTENDED placements.
3. Resolve exploration spawn / Boss pressure / event contact.
4. Emit event_interaction_requested when exploration contacts an unresolved event.
```

`CardChainCoordinator` no longer connects directly to Board. It becomes a pure placement reaction service with:

```gdscript
func configure(board: Board) -> bool
func resolve_placement(result: BoardPlacementResult) -> int
```

`ExplorationCoordinator` remains responsible for event spawning, Boss pressure, and Boss dismissal, but no longer depends on GameManager's direct Board callback.

### 4.4 RunFlowCoordinator

**New file:** `scripts/game/run/run_flow_coordinator.gd`

Owns run-state transitions and cross-domain gameplay orchestration.

```gdscript
enum State { UNINITIALIZED, EXPLORING, INTERACTING, FAILED, FINISHED }
signal state_changed(previous: State, current: State)
signal combat_started(instance: EventInstance, monster: MobInstance)
signal combat_resolved(instance: EventInstance, result: CombatResult)
signal exploration_failed(result: CombatResult)
signal run_finished
signal player_state_changed
signal interaction_lock_requested(locked: bool)
```

Responsibilities:

- binds PlacementPipeline event requests to EventModalCoordinator;
- passes current `RunContext.player_stats` and board combat chain when an event starts;
- receives modal combat settlement requests;
- applies settlement once through EncounterResolutionCoordinator;
- completes the modal lifecycle only after successful settlement;
- transitions defeat to `FAILED` and forces interaction lock;
- transitions a Boss victory to `FINISHED` and emits `run_finished`;
- binds FaithService confirmed retractions and routes faith echo requests to ExplorationCoordinator;
- exposes player state changes for presentation.

It must never use UI widget methods except the injected DragLayer interaction source needed to receive confirmed retraction. Locking is emitted as a request and handled by presentation.

### 4.5 EventModalCoordinator settlement contract

`EventModalCoordinator.confirm_combat_settlement()` changes behavior:

```text
Current: hide combat view → emit request
Target:  emit request while combat view remains visible
```

On a successful apply, `RunFlowCoordinator` calls `complete_combat_settlement()`, which hides the view and completes `EventInteractionController` state. On failure, the view and pending interaction remain available; the coordinator reports an error but does not leave a hidden locked modal.

### 4.6 EncounterResolutionCoordinator port

Replace the concrete `ExplorationCoordinator` parameter with a narrow Boss dismissal callback:

```gdscript
boss_dismissed: Callable
```

or equivalent world port. Encounter settlement remains responsible for card/monster/player state effects and rewards, but does not depend on the complete exploration facade type.

### 4.7 RunPresentationCoordinator

**New file:** `scripts/game/run/run_presentation_coordinator.gd`

Owns scene-level presentation adapters:

- HandArea `hand_count_changed` → HandTray;
- FaithService / RunFlow / PersistentMarket player state changes → PilgrimCrestHud;
- RunFlow / EventModal interaction-lock request → DragLayer;
- terminal state prevents unlock requests from reopening input.

It does not apply game rules or mutate domain state.

### 4.8 GameManager after refactor

GameManager retains:

- exported static level data (`player_data`, `event_lib`, `exploration_config`);
- scene node references;
- `configure_run(preset)` before `_ready()`;
- dependency validation;
- creation and wiring of run-level coordinators;
- forwarding public high-level signals to Main;
- optional layout hook, left behaviorally unchanged because the current early return is a user-owned layout decision.

It removes:

- `_is_exploration_failed`;
- `_market_rng`, `_encounter_reward_rng`;
- `_faith_service` direct signal handling;
- `_on_board_placement_committed`;
- direct EventModal begin/settlement handling;
- direct HUD / HandTray / DragLayer synchronization;
- public mutable compatibility arrays as primary ownership APIs.

Temporary read-only compatibility accessors may be retained if existing scenes/tests require them.

## 5. Lifecycle and Event Flow

### 5.1 Initialization

```text
GameManager validates scene + static data
→ RunSetupCoordinator creates RunContext
→ build CardChain, Exploration, Pipeline, Modal, Settlement, Flow, Presentation, Market
→ configure all dependencies
→ initialize exploration events
→ Flow enters EXPLORING
```

Configuration is atomic at the run level: if any required coordinator cannot configure, GameManager emits `run_initialization_failed`, does not enter EXPLORING, and does not expose a partially usable run.

### 5.2 Normal placement

```text
Board.placement_committed
→ PlacementPipelineCoordinator
→ CardChainCoordinator.resolve_placement
→ ExplorationCoordinator.resolve_placement
→ event_interaction_requested (if contact)
→ RunFlowCoordinator enters INTERACTING
→ EventModalCoordinator begins the ordinary event flow
```

### 5.3 Combat settlement

```text
Combat view confirmation
→ EventModalCoordinator emits settlement request (view remains visible)
→ RunFlowCoordinator
→ EncounterResolutionCoordinator.apply
    ├─ victory: rewards + resolve event + dismiss Boss through port
    ├─ retreat: persist monster, return tail, strengthen monster
    └─ defeat: update state and emit failure
→ success: EventModalCoordinator.complete_combat_settlement
→ Flow transitions EXPLORING / FAILED / FINISHED
```

### 5.4 Faith retraction

```text
DragLayer.chain_retraction_confirmed
→ RunFlowCoordinator
→ FaithService.resolve_confirmed_chain_retraction
→ FaithService.echo_spawn_requested (faith <= 0)
→ ExplorationCoordinator.request_faith_echo
```

## 6. Non-goals

This refactor explicitly does not:

- change combat point/armor rules;
- change CardRule effect design or card data;
- redesign Ribwood map progression or event resources;
- add UI for faith, Boss phase, or run completion;
- change Boss pursuit thresholds;
- make all modules fully dependency-inversion/port-adapter based;
- remove the existing `_center_layout()` early return.

## 7. Compatibility Decisions

- Existing `combat_started`, `combat_resolved`, `exploration_failed`, `run_initialization_failed`, `run_finished`, and `faith_changed` GameManager signals remain public.
- Boss interaction remains contact-driven, never click-driven.
- Existing `BoardPlacementResult.Kind` values remain intact.
- Existing EventModal views remain unchanged except settlement confirmation timing.
- Existing EventLib/ExplorationConfig resources remain valid.
- Existing `RunCardService` remains the source of card ownership. GameManager compatibility arrays, if retained, are exposed only as read-only aliases during this migration.

## 8. Test Strategy

### New unit tests

1. `placement_pipeline_coordinator_test.gd`
   - pipeline is the only Board placement subscriber;
   - card rules resolve before exploration;
   - pipeline ignores placements outside EXPLORING;
   - normal event contact is emitted once.

2. `run_context_test.gd`
   - context exposes one stable runtime player/card/stat graph;
   - seeded random streams reproduce results.

3. `run_flow_coordinator_test.gd`
   - state transitions: EXPLORING → INTERACTING → EXPLORING;
   - defeat locks input and enters FAILED;
   - Boss victory reaches FINISHED and emits run_finished;
   - failed settlement keeps modal interaction recoverable;
   - faith echo request delegates to exploration.

4. `run_presentation_coordinator_test.gd`
   - hand count updates tray;
   - player state updates crest;
   - FAILED prevents later unlock requests.

### Updated tests

- `card_chain_coordinator_test.gd`: coordinator is invoked by pipeline rather than listening to Board itself.
- `game_manager_run_setup_test.gd`: verifies GameManager composes the pipeline and no longer owns direct Board placement forwarding.
- `game_manager_architecture_test.gd`: replaces source-string-only assertions with runtime composition assertions where possible.
- `game_manager_combat_routing_test.gd`: verifies normal monster/Boss contact flow and terminal run completion.
- `event_modal_coordinator_test.gd`: confirmation no longer hides the modal before settlement succeeds.
- `encounter_resolution_coordinator_test.gd`: Boss dismissal uses the callback port.

### Verification

1. Fresh Godot editor scan.
2. Targeted unit and integration tests listed above.
3. Full `tests/*.gd` sweep after targeted tests pass.
4. `gdformat --check` for all modified GDScript files.

## 9. Migration Sequence

1. Add RunContext and RunRandomService, migrate RunSetupCoordinator outputs.
2. Add placement pipeline, remove CardChain direct Board subscription, eliminate the missing GameManager placement callback.
3. Add RunFlowCoordinator and convert combat settlement to a success-first modal contract.
4. Add RunPresentationCoordinator and remove GameManager HUD/input/faith wiring.
5. Replace EncounterResolutionCoordinator's ExplorationCoordinator dependency with a Boss dismissal callable.
6. Slim GameManager, update tests, then run full verification.

Each step must preserve a compiling project and pass its targeted tests before proceeding.