# Stateful Combat Session Implementation Plan

> **For Codex:** Execute this plan task-by-task with `superpowers:test-driven-development`. Do not batch tasks together. After each task, run the focused tests, inspect the diff, and create the listed commit.

**Goal:** Replace the synchronous full-combat calculation with a stateful, event-by-event combat session that has explicit trigger timing, separate player/monster attack batches, generic in-combat operation cards, board-facing presentation events, and user-controlled combat speed.

**Architecture:** `CombatSession` is the single authoritative state machine. Commands and triggers enter as pending requests; `CombatIntentResolver` atomically commits one major behavior into immutable `CombatEventBatch` output. Presentation ACK, settlement delay, and interaction holds gate the next advance. UI adapters may preview targets and submit commands, but never mutate combat state directly.

**Tech Stack:** Godot 4.7, GDScript, `RefCounted` domain objects, signals at scene/controller boundaries, headless `SceneTree` tests.

**Design specification:** `docs/superpowers/specs/2026-08-14-combat-session-and-operation-cards-design.md`

## Global execution rules

- Preserve all unrelated working-tree changes. In particular, do not overwrite or stage the user's current card, scene, board, hand, or drag-layer edits.
- Tests use `extends SceneTree` and exit non-zero when an expectation fails.
- Focused test command:

```powershell
$godot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
& $godot --headless --path . --script res://tests/<test_file>.gd
```

- Import/compile check after script or resource changes:

```powershell
& $godot --headless --editor --path . --quit
```

- Before every commit:

```powershell
git diff --check
git status --short
git diff -- <paths owned by the task>
```

- Stage only paths owned by the current task.
- A batch is committed before it is emitted. It is historical fact and cannot be rolled back while its animation is playing.
- Queues contain requests, not calculated damage, target values, or outcomes. Re-read mutable target/state values when dequeuing.

---

## Task 1: Add stable combat entity IDs and immutable protocol DTOs

**Files**

- Modify: `scripts/card/card_instance.gd`
- Create: `scripts/combatv2/protocol/combat_command.gd`
- Create: `scripts/combatv2/protocol/play_combat_operation_command.gd`
- Create: `scripts/combatv2/protocol/combat_trigger_request.gd`
- Create: `scripts/combatv2/protocol/combat_intent.gd`
- Create: `scripts/combatv2/protocol/combat_domain_event.gd`
- Create: `scripts/combatv2/protocol/combat_event_batch.gd`
- Create: `scripts/combatv2/protocol/combat_command_result.gd`
- Test: `tests/combat_protocol_test.gd`

**Consumes**

```gdscript
CardInstance.new(data: CardData, explicit_instance_id: StringName = &"")
```

**Produces**

```gdscript
CardInstance.instance_id: StringName
CardInstance.duplicate_for_combat() -> CardInstance
CombatEventBatch.new(sequence: int, kind: Kind, events: Array[CombatDomainEvent], cause_snapshot: Dictionary)
CombatEventBatch.duplicate_runtime() -> CombatEventBatch
PlayCombatOperationCommand.new(command_id: StringName, operation_card_id: StringName, target_id: StringName)
CombatCommandResult.accepted(command_id: StringName) -> CombatCommandResult
CombatCommandResult.rejected(command_id: StringName, reason: StringName) -> CombatCommandResult
```

### Step 1: Write the failing protocol test

Create `tests/combat_protocol_test.gd`:

```gdscript
extends SceneTree

const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const BatchScript = preload("res://scripts/combatv2/protocol/combat_event_batch.gd")
const EventScript = preload("res://scripts/combatv2/protocol/combat_domain_event.gd")
const CommandScript = preload("res://scripts/combatv2/protocol/play_combat_operation_command.gd")

var _failures := 0

func _init() -> void:
    var data := CardDataScript.new()
    data.card_name = "Root"
    var card := CardInstanceScript.new(data, &"card-root")
    card.current_points = 4
    card.current_armor = 2
    var copy := card.duplicate_for_combat()
    _expect(copy != card, "combat copy is independent")
    _expect(copy.instance_id == &"card-root", "combat copy preserves stable id")
    _expect(copy.current_points == 4 and copy.current_armor == 2, "combat copy preserves runtime values")

    var event := EventScript.new(EventScript.Type.CARD_POINTS_CHANGED, &"card-root", {&"before": 4, &"after": 2})
    var batch := BatchScript.new(7, BatchScript.Kind.PLAYER_ATTACK, [event], {&"source_id": &"card-root"})
    var cloned := batch.duplicate_runtime()
    batch.cause_snapshot[&"source_id"] = &"changed"
    _expect(cloned.sequence == 7, "batch keeps sequence")
    _expect(cloned.cause_snapshot[&"source_id"] == &"card-root", "batch snapshot is copied")

    var command := CommandScript.new(&"cmd-1", &"retreat-card", &"card-root")
    _expect(command.operation_card_id == &"retreat-card" and command.target_id == &"card-root", "command carries ids only")
    quit(1 if _failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    _failures += 1
    push_error(message)
```

### Step 2: Run the test and verify the failure

```powershell
$godot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
& $godot --headless --path . --script res://tests/combat_protocol_test.gd
```

Expected: non-zero exit because the protocol scripts and explicit `CardInstance` ID constructor do not exist.

### Step 3: Implement the minimal DTOs

Use typed `RefCounted` classes with constructor-only payload assignment. Define these enums exactly:

```gdscript
# combat_event_batch.gd
enum Kind {
    COMBAT_START,
    PLAYER_ATTACK,
    CARD_TRIGGER,
    COMBAT_OPERATION,
    MONSTER_ATTACK,
    COMBAT_END,
    COMMAND_REJECTED,
}
```

```gdscript
# combat_trigger_request.gd
enum Type {
    COMBAT_STARTED,
    PLAYER_ATTACK_FINISHED,
    MONSTER_ATTACK_FINISHED,
    CARD_TRIGGER_FINISHED,
    FRONT_CARD_DEPLETED,
}
```

```gdscript
# combat_intent.gd
enum Type {
    DAMAGE_MONSTER,
    DAMAGE_CARD,
    ADD_CARD_POINTS,
    ADD_CARD_SHIELD,
    SPEND_RESOURCE,
    CUT_CHAIN_FROM_TARGET,
    MOVE_CARDS_TO_HAND,
    CONSUME_OPERATION_CARD,
    END_COMBAT,
}
```

```gdscript
# combat_domain_event.gd
enum Type {
    COMBAT_STARTED,
    PLAYER_ATTACK_FINISHED,
    MONSTER_ATTACK_FINISHED,
    CARD_POINTS_CHANGED,
    CARD_SHIELD_CHANGED,
    CARD_DEPLETED,
    CARD_TRIGGER_FINISHED,
    CHAIN_STRUCTURE_CHANGED,
    RESOURCE_CHANGED,
    OPERATION_CARD_CONSUMED,
    COMBAT_OPERATION_RESOLVED,
    COMMAND_REJECTED,
    COMBAT_ENDED,
}
```

Minimum `CardInstance` change:

```gdscript
var instance_id: StringName

func _init(data: CardData, explicit_instance_id: StringName = &"") -> void:
    card_data = data
    instance_id = explicit_instance_id if explicit_instance_id != &"" else StringName(str(ResourceUID.create_id()))
    # Preserve the existing runtime initialization below this point.

func duplicate_for_combat() -> CardInstance:
    var copy := CardInstance.new(card_data, instance_id)
    copy.cur_zone = cur_zone
    copy.battlefield_pos = battlefield_pos
    copy.direction = direction
    copy.current_points = current_points
    copy.current_armor = current_armor
    copy._rule_trigger_counts = _rule_trigger_counts.duplicate(true)
    return copy
```

`CombatEventBatch.duplicate_runtime()` must deep-copy every event and `cause_snapshot`; external callers never receive the session-owned arrays/dictionaries.

### Step 4: Run focused and regression tests

```powershell
& $godot --headless --path . --script res://tests/combat_protocol_test.gd
& $godot --headless --path . --script res://tests/combatv2_service_test.gd
& $godot --headless --editor --path . --quit
```

Expected: all commands exit `0`.

### Step 5: Commit

```powershell
git add scripts/card/card_instance.gd scripts/combatv2/protocol tests/combat_protocol_test.gd
git commit -m "feat: define combat session protocol"
```

---

## Task 2: Build `CombatSessionState` and the atomic intent resolver

**Files**

- Create: `scripts/combatv2/session/combat_session_state.gd`
- Create: `scripts/combatv2/session/combat_intent_resolver.gd`
- Create: `tests/helpers/combat_test_fixtures.gd`
- Test: `tests/combat_session_state_test.gd`
- Test: `tests/combat_intent_resolver_test.gd`

**Consumes**

```gdscript
CombatSessionState.new(player_stats: CombatStats, monster: MobInstance, chain: Array[CardInstance], resources: Dictionary, operation_cards: Array[CardInstance])
CombatIntentResolver.resolve(state: CombatSessionState, intents: Array[CombatIntent]) -> Array[CombatDomainEvent]
```

**Produces**

```gdscript
CombatSessionState.get_card(card_id: StringName) -> CardInstance
CombatSessionState.get_chain_ids() -> Array[StringName]
CombatSessionState.get_resource(resource_id: StringName) -> int
CombatSessionState.is_terminal() -> bool
CombatSessionState.duplicate_result_snapshot() -> Dictionary
```

### Step 1: Write failing state and resolver tests

Create `tests/combat_session_state_test.gd` with this core assertion:

```gdscript
extends SceneTree

const StateScript = preload("res://scripts/combatv2/session/combat_session_state.gd")

func _init() -> void:
    var fixtures := load("res://tests/helpers/combat_test_fixtures.gd")
    var root: CardInstance = fixtures.make_card("Root", 4, &"root")
    var head: CardInstance = fixtures.make_card("Head", 2, &"head")
    var monster: MobInstance = fixtures.make_monster("Echo", 5)
    var state := StateScript.new(null, monster, [root, head], {&"gold": 9}, [])
    assert(state.get_chain_ids() == [&"root", &"head"])
    root.current_points = 0
    assert(state.get_card(&"root").current_points == 4)
    assert(state.get_resource(&"gold") == 9)
    quit(0)
```

Create `tests/helpers/combat_test_fixtures.gd` with explicit-ID helpers used by both tests:

```gdscript
extends RefCounted

static func make_card(display_name: String, points: int, instance_id: StringName) -> CardInstance:
    var data := CardData.new()
    data.card_name = display_name
    data.max_points = points
    return CardInstance.new(data, instance_id)

static func make_monster(display_name: String, health: int) -> MobInstance:
    var stats := CombatStatsData.new()
    stats.max_hp = health
    var data := MobData.new()
    data.mob_name = display_name
    data.base_stats = stats
    return MobInstance.new(data)
```

Create `tests/combat_intent_resolver_test.gd`:

```gdscript
extends SceneTree

const IntentScript = preload("res://scripts/combatv2/protocol/combat_intent.gd")
const EventScript = preload("res://scripts/combatv2/protocol/combat_domain_event.gd")
const ResolverScript = preload("res://scripts/combatv2/session/combat_intent_resolver.gd")
const StateScript = preload("res://scripts/combatv2/session/combat_session_state.gd")

func _init() -> void:
    var fixtures := load("res://tests/helpers/combat_test_fixtures.gd")
    var card: CardInstance = fixtures.make_card("Head", 3, &"head")
    var state := StateScript.new(null, fixtures.make_monster("Echo", 5), [card], {&"gold": 7}, [])
    var intents: Array[CombatIntent] = [
        IntentScript.new(IntentScript.Type.DAMAGE_MONSTER, &"head", &"monster", {&"amount": 3}),
        IntentScript.new(IntentScript.Type.ADD_CARD_SHIELD, &"head", &"head", {&"amount": 2}),
    ]
    var events := ResolverScript.new().resolve(state, intents)
    assert(state.monster.stats.hp == 2)
    assert(state.get_card(&"head").current_armor == 2)
    assert(events.size() == 2)
    assert(events[0].type == EventScript.Type.PLAYER_ATTACK_FINISHED)
    assert(events[1].type == EventScript.Type.CARD_SHIELD_CHANGED)
    quit(0)
```

### Step 2: Run tests and verify failure

```powershell
& $godot --headless --path . --script res://tests/combat_session_state_test.gd
& $godot --headless --path . --script res://tests/combat_intent_resolver_test.gd
```

Expected: both fail because session state and resolver are absent.

### Step 3: Implement state ownership and atomic intent application

`CombatSessionState` must duplicate the monster, chain cards, operation cards, stats, and resource dictionary on construction. Maintain an ID-to-card map for O(1) lookup. Never store scene `Node` references.

Resolver outline:

```gdscript
func resolve(state: CombatSessionState, intents: Array[CombatIntent]) -> Array[CombatDomainEvent]:
    var events: Array[CombatDomainEvent] = []
    for intent in intents:
        match intent.type:
            CombatIntent.Type.DAMAGE_MONSTER:
                events.append(_damage_monster(state, intent))
            CombatIntent.Type.DAMAGE_CARD:
                events.append_array(_damage_card(state, intent))
            CombatIntent.Type.ADD_CARD_POINTS:
                events.append(_add_card_points(state, intent))
            CombatIntent.Type.ADD_CARD_SHIELD:
                events.append(_add_card_shield(state, intent))
            CombatIntent.Type.SPEND_RESOURCE:
                events.append(_spend_resource(state, intent))
            _:
                push_error("Unsupported combat intent: %s" % intent.type)
    return events
```

Each event stores before/after values. A damage-card intent emits `CARD_SHIELD_CHANGED` before `CARD_POINTS_CHANGED`, then `CARD_DEPLETED` when points become zero. Resource spending must reject before mutation if insufficient; the generic operation transaction in Task 6 will validate the complete intent set before calling this resolver.

### Step 4: Run focused tests

```powershell
& $godot --headless --path . --script res://tests/combat_session_state_test.gd
& $godot --headless --path . --script res://tests/combat_intent_resolver_test.gd
& $godot --headless --path . --script res://tests/combat_effect_pipeline_test.gd
& $godot --headless --editor --path . --quit
```

Expected: all commands exit `0`.

### Step 5: Commit

```powershell
git add scripts/combatv2/session/combat_session_state.gd scripts/combatv2/session/combat_intent_resolver.gd tests/combat_session_state_test.gd tests/combat_intent_resolver_test.gd tests/helpers/combat_test_fixtures.gd
git commit -m "feat: add atomic combat state resolver"
```

---

## Task 3: Implement the stateful `CombatSession` and presentation ACK contract

**Files**

- Create: `scripts/combatv2/session/combat_trigger_queue.gd`
- Create: `scripts/combatv2/session/combat_session.gd`
- Test: `tests/combat_session_test.gd`

**Consumes**

```gdscript
CombatSession.new(state: CombatSessionState, intent_resolver: CombatIntentResolver)
CombatSession.start() -> CombatEventBatch
CombatSession.advance_one_event() -> CombatEventBatch
CombatSession.acknowledge_batch(sequence: int) -> bool
CombatSession.submit_command(command: CombatCommand) -> CombatCommandResult
CombatSession.close_operation_window() -> void
```

**Produces**

```gdscript
CombatSession.get_phase() -> Phase
CombatSession.get_pending_batch() -> CombatEventBatch
CombatSession.can_advance() -> bool
CombatSession.is_finished() -> bool
CombatSession.build_result() -> CombatResult
```

### Step 1: Write the failing session test

Create `tests/combat_session_test.gd`:

```gdscript
extends SceneTree

const SessionScript = preload("res://scripts/combatv2/session/combat_session.gd")
const StateScript = preload("res://scripts/combatv2/session/combat_session_state.gd")
const ResolverScript = preload("res://scripts/combatv2/session/combat_intent_resolver.gd")
const BatchScript = preload("res://scripts/combatv2/protocol/combat_event_batch.gd")

func _init() -> void:
    var fixtures := load("res://tests/helpers/combat_test_fixtures.gd")
    var state := StateScript.new(null, fixtures.make_monster("Echo", 5), [fixtures.make_card("Head", 3, &"head")], {}, [])
    var session := SessionScript.new(state, ResolverScript.new())

    var started := session.start()
    assert(started.kind == BatchScript.Kind.COMBAT_START)
    assert(session.advance_one_event() == null)
    assert(not session.acknowledge_batch(started.sequence + 1))
    assert(session.acknowledge_batch(started.sequence))

    var attack := session.advance_one_event()
    assert(attack != null)
    assert(attack.sequence == started.sequence + 1)
    assert(session.get_pending_batch().sequence == attack.sequence)
    quit(0)
```

### Step 2: Run the test and verify failure

```powershell
& $godot --headless --path . --script res://tests/combat_session_test.gd
```

Expected: non-zero exit because `CombatSession` and its ACK state do not exist.

### Step 3: Implement the minimum phase machine

Use this phase enum:

```gdscript
enum Phase {
    CREATED,
    COMBAT_START,
    PLAYER_ATTACK,
    PLAYER_OPERATION_WINDOW,
    POST_PLAYER_TRIGGERS,
    MONSTER_ATTACK,
    POST_MONSTER_TRIGGERS,
    COMBAT_END,
    FINISHED,
    FAULTED,
}
```

Session invariants:

```gdscript
func advance_one_event() -> CombatEventBatch:
    if _pending_batch != null or _phase in [Phase.CREATED, Phase.FINISHED, Phase.FAULTED]:
        return null
    var batch := _resolve_next_request()
    if batch == null:
        return null
    _pending_batch = batch.duplicate_runtime()
    return _pending_batch.duplicate_runtime()

func acknowledge_batch(sequence: int) -> bool:
    if _pending_batch == null or _pending_batch.sequence != sequence:
        return false
    _pending_batch = null
    _transition_after_ack()
    return true
```

`start()` is the only legal transition out of `CREATED`; it atomically creates the `COMBAT_START` batch and marks it pending. `advance_one_event()` commits no more than one major behavior. `submit_command()` only enqueues accepted commands; it never performs an immediate mutation.

For this task, `_resolve_next_request()` may support only combat start and a basic player attack placeholder. Tasks 4–7 replace the placeholder with complete attack, trigger, and operation resolution.

### Step 4: Run focused tests

```powershell
& $godot --headless --path . --script res://tests/combat_session_test.gd
& $godot --headless --path . --script res://tests/combat_protocol_test.gd
& $godot --headless --editor --path . --quit
```

Expected: all commands exit `0`.

### Step 5: Commit

```powershell
git add scripts/combatv2/session/combat_trigger_queue.gd scripts/combatv2/session/combat_session.gd tests/combat_session_test.gd
git commit -m "feat: add stateful combat session"
```

---

## Task 4: Split player attack and monster attack into separate batches

**Files**

- Modify: `scripts/combatv2/session/combat_session.gd`
- Modify: `scripts/combatv2/session/combat_intent_resolver.gd`
- Modify: `scripts/combatv2/combat_service.gd`
- Test: `tests/combat_attack_order_test.gd`
- Modify test: `tests/combatv2_service_test.gd`

**Consumes**

```gdscript
CombatSession.advance_one_event() -> CombatEventBatch
MobInstance.next_action() -> MobAction
```

**Produces**

```gdscript
CombatSession._build_player_attack_intents(card_id: StringName) -> Array[CombatIntent]
CombatSession._build_monster_attack_intents(card_id: StringName) -> Array[CombatIntent]
```

### Step 1: Write the failing attack-order test

Create `tests/combat_attack_order_test.gd`:

```gdscript
extends SceneTree

const SessionScript = preload("res://scripts/combatv2/session/combat_session.gd")
const StateScript = preload("res://scripts/combatv2/session/combat_session_state.gd")
const ResolverScript = preload("res://scripts/combatv2/session/combat_intent_resolver.gd")
const BatchScript = preload("res://scripts/combatv2/protocol/combat_event_batch.gd")
const EventScript = preload("res://scripts/combatv2/protocol/combat_domain_event.gd")

func _init() -> void:
    _test_attacks_are_distinct_batches()
    _test_lethal_player_attack_skips_monster_attack()
    quit(0)

func _test_attacks_are_distinct_batches() -> void:
    var session := _make_session(3, 5)
    _ack(session, session.start())
    var player_batch := session.advance_one_event()
    assert(player_batch.kind == BatchScript.Kind.PLAYER_ATTACK)
    assert(_count(player_batch, EventScript.Type.MONSTER_ATTACK_FINISHED) == 0)
    _ack(session, player_batch)

    session.close_operation_window()
    var monster_batch := _advance_until_kind(session, BatchScript.Kind.MONSTER_ATTACK)
    assert(monster_batch != null)
    assert(_count(monster_batch, EventScript.Type.PLAYER_ATTACK_FINISHED) == 0)

func _test_lethal_player_attack_skips_monster_attack() -> void:
    var session := _make_session(5, 5)
    _ack(session, session.start())
    _ack(session, session.advance_one_event())
    session.close_operation_window()
    var terminal := _advance_until_kind(session, BatchScript.Kind.COMBAT_END)
    assert(terminal != null)
    assert(session.state.monster.stats.hp == 0)

func _ack(session, batch) -> void:
    assert(batch != null and session.acknowledge_batch(batch.sequence))

func _advance_until_kind(session, kind: int):
    for index in range(8):
        var batch = session.advance_one_event()
        if batch == null:
            continue
        if batch.kind == kind:
            return batch
        _ack(session, batch)
    return null

func _count(batch, type: int) -> int:
    return batch.events.filter(func(event): return event.type == type).size()

func _make_session(card_points: int, monster_health: int):
    var fixtures := load("res://tests/helpers/combat_test_fixtures.gd")
    var state := StateScript.new(null, fixtures.make_monster("Echo", monster_health), [fixtures.make_card("Head", card_points, &"head")], {}, [])
    return SessionScript.new(state, ResolverScript.new())
```

Add helpers required by the snippet directly in this test rather than relying on implicit framework behavior.

### Step 2: Run the test and verify failure

```powershell
& $godot --headless --path . --script res://tests/combat_attack_order_test.gd
```

Expected: non-zero exit because player damage and retaliation are still resolved together or the operation-window transition is absent.

### Step 3: Move clash behavior behind distinct request types

Required ordering:

```text
PLAYER_ATTACK
→ immediate terminal check
→ PLAYER_OPERATION_WINDOW
→ POST_PLAYER_TRIGGERS
→ MONSTER_ATTACK
```

Player batch intents may damage only the monster. Monster batch intents may damage only the current target card. The batch `cause_snapshot` records source card ID, target ID, requested amount, and attack phase; it does not store a reference to a mutable card.

Remove the mixed player/monster `CombatEffectDraft` construction from `_resolve_card_clash()` in `combat_service.gd`. Keep `resolve_encounter()` temporarily as a compatibility adapter that repeatedly advances and ACKs a session until it can build a `CombatResult`. Mark it internal/legacy in its doc comment; callers are migrated in Task 11.

Terminal check rule:

```gdscript
func _after_player_attack_committed() -> void:
    if state.monster.stats.hp <= 0:
        _enqueue_combat_end(CombatResult.Outcome.VICTORY)
        return
    _phase = Phase.PLAYER_OPERATION_WINDOW
```

Do not enqueue a monster attack until the operation window is closed and post-player triggers are exhausted.

### Step 4: Run focused and combat regressions

```powershell
& $godot --headless --path . --script res://tests/combat_attack_order_test.gd
& $godot --headless --path . --script res://tests/combatv2_service_test.gd
& $godot --headless --path . --script res://tests/ribwood_combat_balance_test.gd
& $godot --headless --editor --path . --quit
```

Expected: all commands exit `0`; existing balance outcomes remain unchanged even though their internal event batching is now separated.

### Step 5: Commit

```powershell
git add scripts/combatv2/session/combat_session.gd scripts/combatv2/session/combat_intent_resolver.gd scripts/combatv2/combat_service.gd tests/combat_attack_order_test.gd tests/combatv2_service_test.gd
git commit -m "refactor: separate combat attack phases"
```

---

## Task 5: Replace implicit rule timing with an explicit trigger queue and dispatcher

**Files**

- Create: `scripts/combatv2/session/combat_rule_dispatcher.gd`
- Modify: `scripts/combatv2/session/combat_trigger_queue.gd`
- Modify: `scripts/combatv2/session/combat_session.gd`
- Modify: `scripts/combatv2/protocol/combat_trigger_request.gd`
- Modify: `scripts/combatv2/card/card_rule.gd`
- Modify: `scripts/combatv2/card/rules/armored_next_card_point_bonus_rule.gd`
- Modify: `scripts/combatv2/card/rules/behind_head_pre_trigger_rule.gd`
- Modify: `scripts/combatv2/card/rules/card_damage_multiplier_rule.gd`
- Modify: `scripts/combatv2/card/rules/chain_length_head_armor_bonus_rule.gd`
- Modify: `scripts/combatv2/card/rules/chain_length_head_point_bonus_rule.gd`
- Modify: `scripts/combatv2/card/rules/combat_start_point_bonus_rule.gd`
- Modify: `scripts/combatv2/card/rules/first_card_damage_double_rule.gd`
- Modify: `scripts/combatv2/card/rules/last_card_defense_bonus_rule.gd`
- Modify: `scripts/combatv2/card/rules/last_card_defense_double_rule.gd`
- Modify: `scripts/combatv2/card/rules/next_card_armor_bonus_rule.gd`
- Modify: `scripts/combatv2/card/rules/next_card_point_bonus_rule.gd`
- Modify: `scripts/combatv2/card/rules/previous_defense_damage_bonus_rule.gd`
- Modify: `scripts/combatv2/card/rules/previous_defense_heal_bonus_rule.gd`
- Modify: `scripts/combatv2/card/rules/previous_weapon_damage_bonus_rule.gd`
- Modify: `scripts/combatv2/card/rules/previous_weapon_damage_double_rule.gd`
- Modify: `scripts/combatv2/mob_effect.gd`
- Modify: `scripts/combatv2/mob_effects/mob_effect_rear_shock.gd`
- Modify: `scripts/combatv2/mob_effects/mob_effect_shield_break.gd`
- Test: `tests/combat_trigger_queue_test.gd`
- Modify test: `tests/combatv2_card_rule_test.gd`

**Consumes**

```gdscript
CombatTriggerQueue.enqueue(request: CombatTriggerRequest) -> void
CombatTriggerQueue.dequeue() -> CombatTriggerRequest
CombatTriggerRequest.survival_policy: int
CombatTriggerRequest.root_cause_id: StringName
CombatRuleDispatcher.collect(state: CombatSessionState, request: CombatTriggerRequest) -> Array[CombatTriggerRequest]
CombatRuleDispatcher.build_intents(state: CombatSessionState, request: CombatTriggerRequest) -> Array[CombatIntent]
```

**Produces**

```gdscript
CardRule.get_supported_triggers() -> Array[int]
CardRule.matches_trigger(context: Dictionary) -> bool
CardRule.build_intents(context: Dictionary) -> Array[CombatIntent]
MobEffect.get_supported_triggers() -> Array[int]
MobEffect.build_intents(context: Dictionary) -> Array[CombatIntent]
```

### Step 1: Write the failing trigger-queue test

Create `tests/combat_trigger_queue_test.gd`:

```gdscript
extends SceneTree

const QueueScript = preload("res://scripts/combatv2/session/combat_trigger_queue.gd")
const TriggerScript = preload("res://scripts/combatv2/protocol/combat_trigger_request.gd")

func _init() -> void:
    var queue := QueueScript.new()
    queue.enqueue(TriggerScript.new(TriggerScript.Type.COMBAT_STARTED, &"root", {}, 20))
    queue.enqueue(TriggerScript.new(TriggerScript.Type.FRONT_CARD_DEPLETED, &"head", {}, 10))
    queue.enqueue(TriggerScript.new(TriggerScript.Type.CARD_TRIGGER_FINISHED, &"scout", {}, 10))

    assert(queue.dequeue().source_id == &"head")
    assert(queue.dequeue().source_id == &"scout")
    assert(queue.dequeue().source_id == &"root")
    assert(queue.is_empty())
    quit(0)
```

Extend the same file with survival and loop-guard cases:

```gdscript
func _test_depleted_source_obeys_survival_policy() -> void:
    var queue := QueueScript.new()
    queue.enqueue(TriggerScript.new(TriggerScript.Type.FRONT_CARD_DEPLETED, &"head", {}, 10, TriggerScript.SurvivalPolicy.ALLOW_SOURCE_DEPLETED))
    var state := _make_state_with_depleted_card(&"head")
    assert(queue.dequeue_next_valid(state).source_id == &"head")

    queue.enqueue(TriggerScript.new(TriggerScript.Type.CARD_TRIGGER_FINISHED, &"head", {}, 10, TriggerScript.SurvivalPolicy.REQUIRE_SOURCE_ACTIVE))
    assert(queue.dequeue_next_valid(state) == null)

func _test_trigger_chain_limit_faults_instead_of_looping() -> void:
    var session := _make_self_repeating_trigger_session()
    session.max_triggers_per_atomic_chain = 4
    _ack(session, session.start())
    for index in range(8):
        var batch := session.advance_one_event()
        if batch == null:
            break
        _ack(session, batch)
    assert(session.get_phase() == CombatSession.Phase.FAULTED)
    assert(session.get_fault()[&"reason"] == &"trigger_chain_limit_exceeded")
```

Define survival policy flags on `CombatTriggerRequest`: `REQUIRE_SOURCE_ACTIVE`, `REQUIRE_SOURCE_PRESENT`, `ALLOW_SOURCE_DEPLETED`, `REQUIRE_TARGET_ACTIVE`, `REQUIRE_TARGET_PRESENT`, `RETARGET_ON_RESOLVE`, `CANCEL_ON_COMBAT_END`, and `EXECUTE_DURING_COMBAT_END`.

Extend `tests/combatv2_card_rule_test.gd` with a session-level case:

```gdscript
func _test_finished_trigger_can_enqueue_follow_up_trigger() -> void:
    var session := _make_chain_reaction_session()
    _ack(session, session.start())
    var first_trigger := _advance_until_kind(session, CombatEventBatch.Kind.CARD_TRIGGER)
    _ack(session, first_trigger)
    var second_trigger := _advance_until_kind(session, CombatEventBatch.Kind.CARD_TRIGGER)
    _expect(first_trigger.cause_snapshot[&"source_id"] == &"starter", "starter resolves first")
    _expect(second_trigger.cause_snapshot[&"source_id"] == &"follower", "completion trigger resolves second")
```

The fixture uses two test rules: one supports `COMBAT_STARTED`; the other supports `CARD_TRIGGER_FINISHED` for source `starter`.

### Step 2: Run the tests and verify failure

```powershell
& $godot --headless --path . --script res://tests/combat_trigger_queue_test.gd
& $godot --headless --path . --script res://tests/combatv2_card_rule_test.gd
```

Expected: queue priority/order and completion-trigger chaining are not yet available.

### Step 3: Implement deterministic trigger scheduling

Queue order is `(priority ascending, insertion_sequence ascending)`. A trigger request contains type, source ID, cause snapshot, priority, and insertion sequence. It contains no resolved amount.

Dispatcher algorithm:

```gdscript
func collect(state: CombatSessionState, request: CombatTriggerRequest) -> Array[CombatTriggerRequest]:
    var matches: Array[CombatTriggerRequest] = []
    for card_id in state.get_chain_ids():
        var card := state.get_card(card_id)
        for rule_index in range(card.card_data.effect_rules.size()):
            var rule: CardRule = card.card_data.effect_rules[rule_index]
            if request.type not in rule.get_supported_triggers():
                continue
            var context := _build_context(state, request, card, rule_index)
            if rule.matches_trigger(context) and card.can_trigger_rule(rule_index, rule.effective_count):
                matches.append(CombatTriggerRequest.new(request.type, card_id, request.cause_snapshot, rule.priority))
    return matches
```

When a card rule resolves, record its trigger count, emit `CARD_TRIGGER_FINISHED`, then enqueue `CARD_TRIGGER_FINISHED` with a cause snapshot containing the completed source card/rule IDs. When a front/current card becomes depleted, enqueue `FRONT_CARD_DEPLETED`. Do not recursively execute a trigger during event construction; every rule resolution must become its own `CARD_TRIGGER` batch.

Before dequeuing, enforce the request's survival policy against the latest session state. Ordinary ongoing effects default to active source/target plus `CANCEL_ON_COMBAT_END`; death effects explicitly use `ALLOW_SOURCE_DEPLETED`. Only requests marked `EXECUTE_DURING_COMBAT_END` may survive the ending phase. `RETARGET_ON_RESOLVE` is opt-in; fixed operation-card targets never use it.

Track a monotonically increasing trigger sequence, `root_cause_id`, atomic-chain depth, and per-session trigger count. Default guards are 64 triggers per atomic chain and 512 per combat. Exceeding either guard faults the session with `trigger_chain_limit_exceeded` rather than recursing or hanging.

Adapt every existing card rule and mob effect listed under **Files** to emit intents instead of mutating a draft. Preserve existing exported fields so `.tres` resources continue loading. Keep a temporary draft-to-intent compatibility helper only inside this task if needed to migrate one resource at a time; remove that helper before the task commit.

### Step 4: Run focused and rule regressions

```powershell
& $godot --headless --path . --script res://tests/combat_trigger_queue_test.gd
& $godot --headless --path . --script res://tests/combatv2_card_rule_test.gd
& $godot --headless --path . --script res://tests/combat_effect_pipeline_test.gd
& $godot --headless --path . --script res://tests/ribwood_combat_balance_test.gd
& $godot --headless --editor --path . --quit
```

Expected: all commands exit `0`; rule order is deterministic and each trigger is independently observable.

### Step 5: Commit

```powershell
git add scripts/combatv2/session/combat_rule_dispatcher.gd scripts/combatv2/session/combat_trigger_queue.gd scripts/combatv2/session/combat_session.gd scripts/combatv2/protocol/combat_trigger_request.gd scripts/combatv2/card/card_rule.gd scripts/combatv2/card/rules scripts/combatv2/mob_effect.gd scripts/combatv2/mob_effects tests/combat_trigger_queue_test.gd tests/combatv2_card_rule_test.gd
git commit -m "refactor: make combat trigger timing explicit"
```

---

## Task 6: Define generic combat-operation cards and transactional resolution

**Files**

- Modify: `scripts/card/card_data.gd`
- Create: `scripts/combatv2/operation/combat_operation_definition.gd`
- Create: `scripts/combatv2/operation/combat_target_spec.gd`
- Create: `scripts/combatv2/operation/combat_cost_spec.gd`
- Create: `scripts/combatv2/operation/card_disposition_spec.gd`
- Create: `scripts/combatv2/operation/combat_operation_effect.gd`
- Create: `scripts/combatv2/operation/combat_operation_resolver.gd`
- Modify: `scripts/combatv2/session/combat_session.gd`
- Create: `tests/helpers/combat_operation_test_fixture.gd`
- Test: `tests/combat_operation_resolver_test.gd`
- Test: `tests/combat_pending_request_revalidation_test.gd`

**Consumes**

```gdscript
CardData.combat_operation: CombatOperationDefinition
CombatOperationResolver.validate(state: CombatSessionState, command: PlayCombatOperationCommand) -> CombatCommandResult
CombatOperationResolver.resolve(state: CombatSessionState, command: PlayCombatOperationCommand, sequence: int) -> CombatEventBatch
```

**Produces**

```gdscript
CombatOperationDefinition.target_spec: CombatTargetSpec
CombatOperationDefinition.cost_spec: CombatCostSpec
CombatOperationDefinition.disposition_spec: CardDispositionSpec
CombatOperationDefinition.effects: Array[CombatOperationEffect]
CombatSessionState.get_operation_card(card_id: StringName) -> CardInstance
CombatOperationEffect.build_intents(context: Dictionary) -> Array[CombatIntent]
```

### Step 1: Write the failing operation-resolver test

Create `tests/combat_operation_resolver_test.gd`:

```gdscript
extends SceneTree

const ResolverScript = preload("res://scripts/combatv2/operation/combat_operation_resolver.gd")
const CommandScript = preload("res://scripts/combatv2/protocol/play_combat_operation_command.gd")
const BatchScript = preload("res://scripts/combatv2/protocol/combat_event_batch.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_operation_test_fixture.gd").new()
    var state: CombatSessionState = fixture.make_state_with_operation_card(10)
    var command := CommandScript.new(&"cmd-1", &"operation-1", &"head")
    var resolver := ResolverScript.new()

    var validation := resolver.validate(state, command)
    assert(validation.is_accepted)
    var batch := resolver.resolve(state, command, 1)
    assert(batch.kind == BatchScript.Kind.COMBAT_OPERATION)
    assert(state.get_resource(&"gold") == 7)
    assert(state.get_card(&"head").current_armor == 2)
    assert(state.get_operation_card(&"operation-1") == null)

    var second := resolver.validate(state, command)
    assert(not second.is_accepted)
    assert(second.reason == &"operation_card_missing")
    quit(0)
```

`combat_operation_test_fixture.gd` creates an operation definition with a three-gold cost, fixed card target, consume-on-success disposition, and a two-shield test effect.

Create `tests/combat_pending_request_revalidation_test.gd`:

```gdscript
extends SceneTree

const CommandScript = preload("res://scripts/combatv2/protocol/play_combat_operation_command.gd")
const BatchScript = preload("res://scripts/combatv2/protocol/combat_event_batch.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_operation_test_fixture.gd").new()
    var session: CombatSession = fixture.make_queued_monster_attack_session()
    _ack(session, session.start())

    var committed_player_attack := session.advance_one_event()
    var historical_cause := committed_player_attack.cause_snapshot.duplicate(true)
    _ack(session, committed_player_attack)

    assert(session.submit_command(CommandScript.new(&"shield-1", &"shield-card", &"head")).is_accepted)
    session.close_operation_window()
    var operation := session.advance_one_event()
    _ack(session, operation)
    var monster_attack := _advance_until_kind(session, BatchScript.Kind.MONSTER_ATTACK)

    assert(committed_player_attack.cause_snapshot == historical_cause)
    assert(monster_attack.cause_snapshot[&"target_shield_before"] == 3)
    assert(session.state.get_card(&"head").current_armor == 1)
    quit(0)
```

The fixture gives the operation `+3` shield and the pending monster attack `2` damage. The assertion proves that the already committed player batch remains unchanged while the uncommitted monster request reads the latest shield at dequeue time.

Add another case to `tests/combat_operation_resolver_test.gd` that submits two three-gold commands while five gold is visible. The first command resolves; the second emits `COMMAND_REJECTED` with `insufficient_resource`, consumes no second card, and does not auto-retarget.

### Step 2: Run the tests and verify failure

```powershell
& $godot --headless --path . --script res://tests/combat_operation_resolver_test.gd
& $godot --headless --path . --script res://tests/combat_pending_request_revalidation_test.gd
```

Expected: non-zero exit because operation definitions and resolver do not exist.

### Step 3: Implement validate-then-commit operation resolution

Add to `CardData`:

```gdscript
@export_group("Combat Operation")
@export var combat_operation: CombatOperationDefinition
```

Validation order:

1. Command ID has not already been accepted.
2. Session is in `PLAYER_OPERATION_WINDOW`.
3. Operation card exists in the session operation-card map.
4. Card has a `combat_operation` definition.
5. Target exists and matches `CombatTargetSpec`.
6. Cost is affordable.
7. Every effect can build valid intents for the current state.
8. Card disposition is legal.

Resolver then builds a complete intent array, validates that array without mutation, and commits it once through `CombatIntentResolver`. On failure, return `CombatCommandResult.rejected(...)` and do not spend, move, consume, or mutate anything.

Minimum resolver shape:

```gdscript
func resolve(state: CombatSessionState, command: PlayCombatOperationCommand, sequence: int) -> CombatEventBatch:
    var validation := validate(state, command)
    if not validation.is_accepted:
        return _rejection_batch(sequence, command, validation.reason)
    var operation_card := state.get_operation_card(command.operation_card_id)
    var definition := operation_card.card_data.combat_operation
    var context := _build_context(state, command, operation_card, definition)
    var intents: Array[CombatIntent] = []
    intents.append_array(definition.cost_spec.build_intents(context))
    for effect in definition.effects:
        intents.append_array(effect.build_intents(context))
    intents.append_array(definition.disposition_spec.build_intents(context))
    var events := _intent_resolver.resolve(state, intents)
    events.append(CombatDomainEvent.new(CombatDomainEvent.Type.COMBAT_OPERATION_RESOLVED, command.operation_card_id, {&"command_id": command.command_id, &"target_id": command.target_id}))
    return CombatEventBatch.new(sequence, CombatEventBatch.Kind.COMBAT_OPERATION, events, {&"command_id": command.command_id, &"operation_card_id": command.operation_card_id, &"target_id": command.target_id})
```

`CombatSession.submit_command()` accepts valid commands in submission order and stores command IDs for idempotency. Dequeue-time validation runs again because earlier commands may have changed target, cost, or chain state. Invalid fixed targets reject; never auto-retarget.

### Step 4: Run focused tests

```powershell
& $godot --headless --path . --script res://tests/combat_operation_resolver_test.gd
& $godot --headless --path . --script res://tests/combat_pending_request_revalidation_test.gd
& $godot --headless --path . --script res://tests/combat_session_test.gd
& $godot --headless --path . --script res://tests/combat_protocol_test.gd
& $godot --headless --editor --path . --quit
```

Expected: all commands exit `0`.

### Step 5: Commit

```powershell
git add scripts/card/card_data.gd scripts/combatv2/operation scripts/combatv2/session/combat_session.gd tests/combat_operation_resolver_test.gd tests/combat_pending_request_revalidation_test.gd tests/helpers/combat_operation_test_fixture.gd
git commit -m "feat: add generic combat operation pipeline"
```

---

## Task 7: Implement retreat and gold-for-shield operation effects

**Files**

- Create: `scripts/combatv2/operation/retreat_operation_effect.gd`
- Create: `scripts/combatv2/operation/add_card_shield_operation_effect.gd`
- Modify: `scripts/combatv2/session/combat_intent_resolver.gd`
- Modify: `scripts/combatv2/session/combat_session.gd`
- Modify: `tests/helpers/combat_operation_test_fixture.gd`
- Test: `tests/combat_retreat_operation_test.gd`
- Test: `tests/combat_gold_shield_operation_test.gd`

**Consumes**

```gdscript
RetreatOperationEffect.build_intents(context: Dictionary) -> Array[CombatIntent]
AddCardShieldOperationEffect.build_intents(context: Dictionary) -> Array[CombatIntent]
```

**Produces**

```gdscript
CombatSessionState.returned_card_ids: Array[StringName]
CombatSessionState.consumed_operation_card_ids: Array[StringName]
CombatSessionState.retreat_requested: bool
```

### Step 1: Write the failing retreat test

Create `tests/combat_retreat_operation_test.gd`:

```gdscript
extends SceneTree

const CommandScript = preload("res://scripts/combatv2/protocol/play_combat_operation_command.gd")
const BatchScript = preload("res://scripts/combatv2/protocol/combat_event_batch.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_operation_test_fixture.gd").new()
    var session: CombatSession = fixture.make_retreat_session([&"root", &"b", &"a", &"c", &"head"])
    _ack(session, session.start())
    var attack := session.advance_one_event()
    _ack(session, attack)

    var accepted := session.submit_command(CommandScript.new(&"retreat-1", &"retreat-card", &"a"))
    assert(accepted.is_accepted)
    session.close_operation_window()
    var operation := session.advance_one_event()
    assert(operation.kind == BatchScript.Kind.COMBAT_OPERATION)
    assert(session.state.get_chain_ids() == [&"root", &"b"])
    assert(session.state.returned_card_ids == [&"a", &"c", &"head"])
    assert(session.state.consumed_operation_card_ids == [&"retreat-card"])
    _ack(session, operation)

    var ending := _advance_until_kind(session, BatchScript.Kind.COMBAT_END)
    assert(ending != null)
    assert(session.build_result().outcome == CombatResult.Outcome.RETREAT)
    assert(session.state.monster.enhancement_stacks == 1)
    assert(not _session_emitted_kind(session, BatchScript.Kind.MONSTER_ATTACK))
    quit(0)
```

Add a second case that targets an ID absent from the current chain and asserts: rejection batch, unchanged chain, unchanged monster enhancement, and unconsumed retreat card.

### Step 2: Write the failing gold-for-shield test

Create `tests/combat_gold_shield_operation_test.gd`:

```gdscript
extends SceneTree

const CommandScript = preload("res://scripts/combatv2/protocol/play_combat_operation_command.gd")
const EventScript = preload("res://scripts/combatv2/protocol/combat_domain_event.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_operation_test_fixture.gd").new()
    var session: CombatSession = fixture.make_gold_shield_session(5, 3)
    _ack(session, session.start())
    _ack(session, session.advance_one_event())

    assert(session.submit_command(CommandScript.new(&"shield-1", &"shield-card", &"head")).is_accepted)
    session.close_operation_window()
    var batch := session.advance_one_event()
    assert(session.state.get_resource(&"gold") == 2)
    assert(session.state.get_card(&"head").current_armor == 3)
    assert(_has_event(batch, EventScript.Type.RESOURCE_CHANGED))
    assert(_has_event(batch, EventScript.Type.CARD_SHIELD_CHANGED))
    assert(_has_event(batch, EventScript.Type.OPERATION_CARD_CONSUMED))
    quit(0)
```

Add insufficient-gold and stale-target cases. Both must reject without partial mutation.

### Step 3: Run tests and verify failure

```powershell
& $godot --headless --path . --script res://tests/combat_retreat_operation_test.gd
& $godot --headless --path . --script res://tests/combat_gold_shield_operation_test.gd
```

Expected: both fail because the concrete effects and chain-cut intents are absent.

### Step 4: Implement concrete effects and retreat termination

Retreat effect intents, in order:

```gdscript
return [
    CombatIntent.new(CombatIntent.Type.CUT_CHAIN_FROM_TARGET, source_id, target_id),
    CombatIntent.new(CombatIntent.Type.MOVE_CARDS_TO_HAND, source_id, target_id),
    CombatIntent.new(CombatIntent.Type.CONSUME_OPERATION_CARD, source_id, source_id),
    CombatIntent.new(CombatIntent.Type.END_COMBAT, source_id, &"combat", {&"outcome": CombatResult.Outcome.RETREAT}),
]
```

The resolver calculates the target index when applying `CUT_CHAIN_FROM_TARGET`, stores the removed ordered IDs, and uses exactly those IDs for `MOVE_CARDS_TO_HAND`. With `root → B → A → C → head` and target `A`, retained IDs are `root, B`; returned IDs are `A, C, head`.

On successful retreat:

- Preserve damage already committed.
- Skip all later triggers and monster attack.
- Include already depleted cards in settlement.
- Do not award victory rewards.
- Call `MobInstance.gain_enhancement()` exactly once.
- Consume the retreat operation card.

Gold-for-shield builds `SPEND_RESOURCE` followed by `ADD_CARD_SHIELD`; its operation definition adds the shared consume-on-success disposition intent. Validate affordability and target existence before any intent commits.

### Step 5: Run focused tests and regressions

```powershell
& $godot --headless --path . --script res://tests/combat_retreat_operation_test.gd
& $godot --headless --path . --script res://tests/combat_gold_shield_operation_test.gd
& $godot --headless --path . --script res://tests/combat_operation_resolver_test.gd
& $godot --headless --path . --script res://tests/combat_attack_order_test.gd
& $godot --headless --path . --script res://tests/combatv2_service_test.gd
& $godot --headless --editor --path . --quit
```

Expected: all commands exit `0`.

### Step 6: Commit

```powershell
git add scripts/combatv2/operation/retreat_operation_effect.gd scripts/combatv2/operation/add_card_shield_operation_effect.gd scripts/combatv2/session/combat_intent_resolver.gd scripts/combatv2/session/combat_session.gd tests/combat_retreat_operation_test.gd tests/combat_gold_shield_operation_test.gd tests/helpers/combat_operation_test_fixture.gd
git commit -m "feat: add in-combat retreat and shield operations"
```

---

## Task 8: Add combat speed, advancement gates, and settlement scheduling

**Files**

- Create: `scripts/combatv2/runtime/combat_speed_controller.gd`
- Create: `scripts/combatv2/runtime/combat_advance_gate.gd`
- Create: `scripts/combatv2/runtime/combat_scheduler.gd`
- Test: `tests/combat_speed_controller_test.gd`
- Test: `tests/combat_scheduler_test.gd`

**Consumes**

```gdscript
CombatSpeedController.set_speed_multiplier(value: float) -> void
CombatAdvanceGate.set_presentation_ready(ready: bool) -> void
CombatAdvanceGate.set_interaction_hold(owner: StringName, active: bool) -> void
CombatScheduler.begin_wait(base_duration_seconds: float) -> void
CombatScheduler.advance(delta_seconds: float) -> bool
```

**Produces**

```gdscript
CombatSpeedController.speed_multiplier: float
CombatSpeedController.speed_changed(multiplier: float)
CombatAdvanceGate.can_advance() -> bool
CombatScheduler.get_remaining_real_seconds() -> float
CombatScheduler.delay_ready: bool
```

### Step 1: Write the failing speed-controller test

Create `tests/combat_speed_controller_test.gd`:

```gdscript
extends SceneTree

const SpeedScript = preload("res://scripts/combatv2/runtime/combat_speed_controller.gd")

func _init() -> void:
    var speed := SpeedScript.new()
    assert(is_equal_approx(speed.speed_multiplier, 1.0))
    speed.set_speed_multiplier(2.0)
    assert(is_equal_approx(speed.scale_duration(1.5), 0.75))
    speed.set_speed_multiplier(0.0)
    assert(is_equal_approx(speed.speed_multiplier, SpeedScript.MIN_SPEED))
    speed.set_speed_multiplier(99.0)
    assert(is_equal_approx(speed.speed_multiplier, SpeedScript.MAX_SPEED))
    quit(0)
```

### Step 2: Write the failing scheduler/gate test

Create `tests/combat_scheduler_test.gd`:

```gdscript
extends SceneTree

const SpeedScript = preload("res://scripts/combatv2/runtime/combat_speed_controller.gd")
const GateScript = preload("res://scripts/combatv2/runtime/combat_advance_gate.gd")
const SchedulerScript = preload("res://scripts/combatv2/runtime/combat_scheduler.gd")

func _init() -> void:
    var speed := SpeedScript.new()
    var gate := GateScript.new()
    var scheduler := SchedulerScript.new(speed, gate)
    scheduler.begin_wait(4.0)
    scheduler.advance(1.0)
    assert(is_equal_approx(scheduler.progress, 0.25))

    speed.set_speed_multiplier(2.0)
    assert(is_equal_approx(scheduler.get_remaining_real_seconds(), 1.5))
    scheduler.advance(1.5)
    assert(scheduler.delay_ready)

    gate.set_presentation_ready(false)
    assert(not scheduler.can_advance())
    gate.set_presentation_ready(true)
    gate.set_interaction_hold(&"operation_drag", true)
    assert(not scheduler.can_advance())
    gate.set_interaction_hold(&"operation_drag", false)
    assert(scheduler.can_advance())
    quit(0)
```

### Step 3: Run tests and verify failure

```powershell
& $godot --headless --path . --script res://tests/combat_speed_controller_test.gd
& $godot --headless --path . --script res://tests/combat_scheduler_test.gd
```

Expected: both fail because runtime timing classes are absent.

### Step 4: Implement speed as combat-time scaling

Name all UI-facing properties and methods “combat speed” / `combat_speed`; do not call this “playback speed”. Suggested bounds:

```gdscript
const MIN_SPEED := 0.25
const MAX_SPEED := 4.0
var speed_multiplier := 1.0

func scale_duration(base_seconds: float) -> float:
    return maxf(base_seconds, 0.0) / speed_multiplier
```

Track scheduler progress in normalized combat time:

```gdscript
func advance(real_delta: float) -> bool:
    if delay_ready:
        return true
    _elapsed_combat_seconds += maxf(real_delta, 0.0) * _speed.speed_multiplier
    progress = clampf(_elapsed_combat_seconds / _base_duration, 0.0, 1.0)
    delay_ready = progress >= 1.0
    return delay_ready

func get_remaining_real_seconds() -> float:
    return maxf(_base_duration - _elapsed_combat_seconds, 0.0) / _speed.speed_multiplier
```

Changing speed therefore preserves elapsed fraction and rescales only the remaining real time.

Gate equation:

```gdscript
func can_advance() -> bool:
    return settlement_delay_ready and presentation_ready and _interaction_holds.is_empty()
```

Interaction holds are keyed by owner so repeated begin/end calls are idempotent. An active card drag uses owner `&"operation_drag"`.

### Step 5: Run focused tests

```powershell
& $godot --headless --path . --script res://tests/combat_speed_controller_test.gd
& $godot --headless --path . --script res://tests/combat_scheduler_test.gd
& $godot --headless --editor --path . --quit
```

Expected: all commands exit `0`.

### Step 6: Commit

```powershell
git add scripts/combatv2/runtime tests/combat_speed_controller_test.gd tests/combat_scheduler_test.gd
git commit -m "feat: add combat speed and advancement gates"
```

---

## Task 9: Add target-only operation preview and a generic drag adapter

**Files**

- Create: `scripts/combatv2/operation/combat_operation_target_preview.gd`
- Create: `scripts/game/event/encounter/combat_operation_drag_adapter.gd`
- Modify: `scripts/game/drag_layer/dragger_layer.gd`
- Create: `tests/helpers/combat_drag_test_fixture.gd`
- Test: `tests/combat_operation_drag_adapter_test.gd`
- Modify test: `tests/dragger_layer_test.gd`
- Modify test: `tests/drag_layer_retraction_test.gd`

**Consumes**

```gdscript
CombatOperationDragAdapter.configure(board_zone: BoardZone, preview_provider: Callable, command_sink: Callable)
CombatOperationDragAdapter.begin_drag(card: CardEntity) -> bool
CombatOperationDragAdapter.update_drag(global_position: Vector2) -> CombatOperationTargetPreview
CombatOperationDragAdapter.finish_drag(global_position: Vector2) -> CombatCommandResult
BoardZone.get_cards() -> Array[Card]
CardEntity.get_card_view_screen_rect() -> Rect2
```

**Produces**

```gdscript
CombatOperationTargetPreview.target_id: StringName
CombatOperationTargetPreview.is_valid: bool
CombatOperationTargetPreview.highlight_style: StringName
CombatOperationTargetPreview.rejection_reason: StringName
DraggerLayer.combat_operation_submitted(command: PlayCombatOperationCommand)
DraggerLayer.combat_operation_drag_hold_changed(active: bool)
DraggerLayer.configure_combat_operation_adapter(adapter: CombatOperationDragAdapter) -> void
```

### Step 1: Write the failing drag-adapter test

Create `tests/combat_operation_drag_adapter_test.gd`:

```gdscript
extends SceneTree

const AdapterScript = preload("res://scripts/game/event/encounter/combat_operation_drag_adapter.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_drag_test_fixture.gd").new()
    var root := fixture.make_board_card(&"root", Rect2(0, 0, 100, 100))
    var head := fixture.make_board_card(&"head", Rect2(50, 0, 100, 100))
    var board := fixture.make_board([root, head])
    var submitted: Array[PlayCombatOperationCommand] = []
    var adapter := AdapterScript.new()
    adapter.configure(
        board,
        func(operation_id: StringName, target_id: StringName): return fixture.valid_preview(target_id),
        func(command: PlayCombatOperationCommand): submitted.append(command); return CombatCommandResult.accepted(command.command_id)
    )

    assert(adapter.begin_drag(fixture.make_operation_card(&"retreat-card")))
    var preview := adapter.update_drag(Vector2(75, 50))
    assert(preview.target_id == &"head")
    assert(preview.is_valid)
    assert(not _has_property(preview, &"returned_card_ids"))
    assert(not _has_property(preview, &"shield_delta"))
    adapter.finish_drag(Vector2(75, 50))
    assert(submitted.size() == 1 and submitted[0].target_id == &"head")
    quit(0)

func _has_property(value: Object, property_name: StringName) -> bool:
    return value.get_property_list().any(func(entry: Dictionary): return entry[&"name"] == property_name)
```

The overlap point is inside both root and head card rectangles. The expected target is the head because the adapter iterates `BoardZone.get_cards()` in reverse chain/draw order.

Add invalid-target and no-target cases. They must submit no command and expose only `target_id`, validity, highlight style, and rejection reason.

### Step 2: Run the test and verify failure

```powershell
& $godot --headless --path . --script res://tests/combat_operation_drag_adapter_test.gd
```

Expected: non-zero exit because the preview DTO and adapter do not exist.

### Step 3: Implement a UI-only adapter

Preview DTO:

```gdscript
class_name CombatOperationTargetPreview
extends RefCounted

var target_id: StringName
var is_valid: bool
var highlight_style: StringName
var rejection_reason: StringName
```

It must not contain a retreat segment, shield delta, future gold, damage, outcome, or source-card disposition.

Hit testing:

```gdscript
func _find_target(global_position: Vector2) -> CardEntity:
    var cards := _board_zone.get_cards()
    for index in range(cards.size() - 1, -1, -1):
        var card := cards[index] as CardEntity
        if card != null and card.get_card_view_screen_rect().has_point(global_position):
            return card
    return null
```

The adapter may highlight/unhighlight targets and construct `PlayCombatOperationCommand`. It must not spend currency, alter the chain, add shield, consume a card, or settle combat.

Integrate into `DraggerLayer` before normal board/market drop handling. If `begin_drag()` returns false, preserve all existing drag behavior. Emit `combat_operation_drag_hold_changed(true)` at accepted drag start and `false` on every finish/cancel path. Reconcile this carefully with the user's current uncommitted `dragger_layer.gd` work rather than replacing the file wholesale.

### Step 4: Run focused and drag regressions

```powershell
& $godot --headless --path . --script res://tests/combat_operation_drag_adapter_test.gd
& $godot --headless --path . --script res://tests/dragger_layer_test.gd
& $godot --headless --path . --script res://tests/drag_layer_retraction_test.gd
& $godot --headless --path . --script res://tests/hand_zone_drag_cancel_test.gd
& $godot --headless --editor --path . --quit
```

Expected: all commands exit `0`; ordinary dragging is unchanged.

### Step 5: Commit

```powershell
git add scripts/combatv2/operation/combat_operation_target_preview.gd scripts/game/event/encounter/combat_operation_drag_adapter.gd scripts/game/drag_layer/dragger_layer.gd tests/combat_operation_drag_adapter_test.gd tests/dragger_layer_test.gd tests/drag_layer_retraction_test.gd tests/helpers/combat_drag_test_fixture.gd
git commit -m "feat: add combat operation target dragging"
```

---

## Task 10: Add the board presentation port and card animation hooks

**Files**

- Create: `scripts/game/event/encounter/combat_presentation_port.gd`
- Create: `scripts/game/event/encounter/combat_presentation_coordinator.gd`
- Modify: `scripts/game/event/encounter/combat_event_view.gd`
- Modify: `scripts/card/card_entity.gd`
- Create: `tests/helpers/combat_presentation_test_fixture.gd`
- Test: `tests/combat_presentation_coordinator_test.gd`
- Modify test: `tests/combat_event_ui_scene_test.gd`
- Modify test: `tests/board_scene_composition_test.gd`

**Consumes**

```gdscript
CombatPresentationCoordinator.configure(port: CombatPresentationPort, speed: CombatSpeedController)
CombatPresentationCoordinator.present(batch: CombatEventBatch) -> void
CombatPresentationPort.find_card(card_id: StringName) -> CardEntity
CombatPresentationPort.show_monster_value(value_id: StringName, before: int, after: int, speed: float) -> void
```

**Produces**

```gdscript
CombatPresentationCoordinator.batch_presented(sequence: int)
CardEntity.request_combat_trigger_feedback(speed_multiplier: float) -> void
CardEntity.request_points_change(before: int, after: int, speed_multiplier: float) -> void
CardEntity.request_shield_change(before: int, after: int, speed_multiplier: float) -> void
CombatEventView.begin_combat(instance: EventInstance, monster: MobInstance) -> void
CombatEventView.show_batch(batch: CombatEventBatch) -> void
CombatEventView.show_settlement(result: CombatResult) -> void
CombatEventView.set_combat_speed(speed_multiplier: float) -> void
```

### Step 1: Write the failing presentation test

Create `tests/combat_presentation_coordinator_test.gd`:

```gdscript
extends SceneTree

const CoordinatorScript = preload("res://scripts/game/event/encounter/combat_presentation_coordinator.gd")
const BatchScript = preload("res://scripts/combatv2/protocol/combat_event_batch.gd")
const EventScript = preload("res://scripts/combatv2/protocol/combat_domain_event.gd")

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_presentation_test_fixture.gd").new()
    var card_view := fixture.make_card_view(&"head")
    var port := fixture.make_port({&"head": card_view})
    var coordinator := CoordinatorScript.new()
    coordinator.configure(port, fixture.make_speed(2.0))

    var events: Array[CombatDomainEvent] = [
        EventScript.new(EventScript.Type.CARD_POINTS_CHANGED, &"head", {&"before": 4, &"after": 2}),
        EventScript.new(EventScript.Type.CARD_SHIELD_CHANGED, &"head", {&"before": 0, &"after": 3}),
        EventScript.new(EventScript.Type.CARD_TRIGGER_FINISHED, &"head", {}),
    ]
    var batch := BatchScript.new(3, BatchScript.Kind.CARD_TRIGGER, events, {})
    coordinator.present(batch)

    assert(card_view.point_requests == [[4, 2, 2.0]])
    assert(card_view.shield_requests == [[0, 3, 2.0]])
    assert(card_view.trigger_feedback_speeds == [2.0])
    assert(coordinator.is_presenting())
    card_view.complete_all_requests()
    assert(not coordinator.is_presenting())
    quit(0)
```

### Step 2: Run the test and verify failure

```powershell
& $godot --headless --path . --script res://tests/combat_presentation_coordinator_test.gd
```

Expected: non-zero exit because presentation routing and card hooks do not exist.

### Step 3: Implement event-to-view routing without concrete animation art

`CombatPresentationPort` is an adapter interface/script, not a domain dependency. Its concrete implementation locates board cards by stable `instance_id` and exposes monster/log/settlement view methods.

Coordinator routing:

```gdscript
match event.type:
    CombatDomainEvent.Type.CARD_POINTS_CHANGED:
        _port.find_card(event.subject_id).request_points_change(event.data[&"before"], event.data[&"after"], _speed.speed_multiplier)
    CombatDomainEvent.Type.CARD_SHIELD_CHANGED:
        _port.find_card(event.subject_id).request_shield_change(event.data[&"before"], event.data[&"after"], _speed.speed_multiplier)
    CombatDomainEvent.Type.CARD_TRIGGER_FINISHED:
        _port.find_card(event.subject_id).request_combat_trigger_feedback(_speed.speed_multiplier)
```

Card hooks may immediately update labels and emit completion signals in this task. Preserve method/signal boundaries so later animation work can replace the immediate completion:

```gdscript
signal combat_feedback_finished(request_id: int)

func request_points_change(before: int, after: int, speed_multiplier: float) -> void:
    _set_points_label(after)
    combat_feedback_finished.emit(_next_feedback_request_id())
```

Use equivalent hooks for shield and trigger shake. The coordinator ACKs only after all requests belonging to the batch finish. Missing/stale card views log a warning and count as immediately complete; they must not deadlock combat.

Replace the full-result replay surface of `CombatEventView` with the five methods listed under **Produces**. Keep the current combat log available by translating each batch to log rows incrementally.

### Step 4: Run focused and UI regressions

```powershell
& $godot --headless --path . --script res://tests/combat_presentation_coordinator_test.gd
& $godot --headless --path . --script res://tests/combat_event_ui_scene_test.gd
& $godot --headless --path . --script res://tests/board_scene_composition_test.gd
& $godot --headless --editor --path . --quit
```

Expected: all commands exit `0`; board cards expose animation interfaces even though visual animation remains immediate/minimal.

### Step 5: Commit

```powershell
git add scripts/game/event/encounter/combat_presentation_port.gd scripts/game/event/encounter/combat_presentation_coordinator.gd scripts/game/event/encounter/combat_event_view.gd scripts/card/card_entity.gd tests/combat_presentation_coordinator_test.gd tests/combat_event_ui_scene_test.gd tests/board_scene_composition_test.gd tests/helpers/combat_presentation_test_fixture.gd
git commit -m "feat: route combat batches to board presentation"
```

---

## Task 11: Wire encounter lifecycle, scheduler, drag operations, and final settlement

**Files**

- Modify: `scripts/game/event/encounter/encounter_combat_flow_coordinator.gd`
- Modify: `scripts/game/event/event_interaction_controller.gd`
- Modify: `scripts/game/event/event_modal_coordinator.gd`
- Modify: `scripts/game/run/run_flow_coordinator.gd`
- Modify: `scripts/game/event/encounter/combat_event_view.gd`
- Test: `tests/event_interaction_controller_test.gd`
- Test: `tests/event_modal_coordinator_test.gd`
- Test: `tests/encounter_resolution_coordinator_test.gd`
- Test: `tests/run_flow_coordinator_test.gd`
- Test: `tests/game_manager_combat_routing_test.gd`

**Consumes**

```gdscript
EncounterCombatFlowCoordinator.create_session(player_stats: CombatStats, chain: Array[CardInstance], monster: MobInstance, operation_cards: Array[CardInstance], resources: Dictionary) -> CombatSession
EventInteractionController.begin(instance: EventInstance, player_stats: CombatStats, chain: Array[CardInstance], operation_cards: Array[CardInstance] = [], resources: Dictionary = {}) -> void
EventInteractionController.acknowledge_combat_batch(sequence: int) -> void
EventInteractionController.submit_combat_command(command: CombatCommand) -> CombatCommandResult
EventInteractionController.set_combat_speed(multiplier: float) -> void
```

**Produces**

```gdscript
EventInteractionController.combat_started(instance: EventInstance, monster: MobInstance)
EventInteractionController.combat_batch_ready(instance: EventInstance, batch: CombatEventBatch)
EventInteractionController.combat_result_ready(instance: EventInstance, result: CombatResult)
EventInteractionController.combat_speed_changed(multiplier: float)
EventInteractionController.get_active_combat_session() -> CombatSession
```

### Step 1: Replace the synchronous controller expectation with a failing session test

Update `tests/event_interaction_controller_test.gd` so the combat test asserts incremental behavior:

```gdscript
func _test_monster_event_streams_batches_before_result() -> void:
    var flow := FakeEncounterCombatFlow.new()
    var controller := EventInteractionController.new()
    controller.configure(flow)
    var batches: Array[CombatEventBatch] = []
    var results: Array[CombatResult] = []
    controller.combat_batch_ready.connect(func(_instance, batch): batches.append(batch))
    controller.combat_result_ready.connect(func(_instance, result): results.append(result))

    controller.begin(_make_monster_event(), _make_stats(), _make_chain(), [], {&"gold": 6})
    assert(controller.get_active_combat_session() != null)
    assert(batches.size() == 1)
    assert(batches[0].kind == CombatEventBatch.Kind.COMBAT_START)
    assert(results.is_empty())

    controller.acknowledge_combat_batch(batches[0].sequence)
    controller.advance_combat_if_ready(999.0)
    assert(batches.size() == 2)
    assert(results.is_empty())
```

Add a terminal case that repeatedly ACKs/advances, asserts exactly one final `combat_result_ready`, then calls `confirm_combat_settlement()` and observes `interaction_finished`.

### Step 2: Add a failing modal wiring test

Update `tests/event_modal_coordinator_test.gd`:

```gdscript
func _test_modal_passes_hand_operation_cards_and_gold_to_combat() -> void:
    var fixture := ModalFixture.new()
    fixture.hand_zone.cards = [fixture.make_operation_card(&"retreat-card")]
    fixture.player.gold = 8
    fixture.modal.begin(fixture.monster_event, fixture.stats, fixture.chain)
    assert(fixture.interaction.last_operation_card_ids == [&"retreat-card"])
    assert(fixture.interaction.last_resources == {&"gold": 8})
```

### Step 3: Run tests and verify failure

```powershell
& $godot --headless --path . --script res://tests/event_interaction_controller_test.gd
& $godot --headless --path . --script res://tests/event_modal_coordinator_test.gd
```

Expected: tests fail because the controller still calls synchronous `resolve()` and immediately emits a full result.

### Step 4: Implement incremental orchestration

`EncounterCombatFlowCoordinator.begin(instance)` still creates/returns the encounter monster. Replace `resolve(...)` at runtime call sites with `create_session(...)`. Keep settlement ownership in the existing encounter resolution layer.

`EventInteractionController` owns:

```gdscript
var _active_combat_session: CombatSession
var _combat_speed := CombatSpeedController.new()
var _advance_gate := CombatAdvanceGate.new()
var _scheduler := CombatScheduler.new(_combat_speed, _advance_gate)
```

Controller loop:

```gdscript
func acknowledge_combat_batch(sequence: int) -> void:
    if _active_combat_session == null:
        return
    if not _active_combat_session.acknowledge_batch(sequence):
        return
    _advance_gate.set_presentation_ready(true)
    _scheduler.begin_wait(_base_delay_for_phase(_active_combat_session.get_phase()))

func advance_combat_if_ready(delta: float) -> void:
    if _active_combat_session == null:
        return
    _scheduler.advance(delta)
    if not _scheduler.can_advance():
        return
    var batch := _active_combat_session.advance_one_event()
    if batch == null:
        return
    _advance_gate.set_presentation_ready(false)
    combat_batch_ready.emit(_active_event, batch)
```

When the ACKed terminal batch leaves the session finished, build the result once, store it as `_pending_combat_result`, clear `_active_combat_session`, and emit `combat_result_ready`. `confirm_combat_settlement()` retains its existing responsibility of ending the event interaction after board/player/monster settlement succeeds.

`EventModalCoordinator` gathers operation cards from `_hand_zone.get_cards()`, maps them to `card_instance`, and passes `{&"gold": _player.gold}`. It connects:

- `combat_batch_ready` → `CombatEventView.show_batch()` / presentation coordinator.
- presentation `batch_presented` → `acknowledge_combat_batch()`.
- drag adapter command → `submit_combat_command()`.
- drag hold → advancement gate interaction hold.
- combat-speed control → `set_combat_speed()`.

Keep `RunFlowCoordinator`'s external call shape unchanged if possible:

```gdscript
_modal.begin(instance, _context.player_stats, _board.board_zone.get_combat_card_chain())
```

The modal already owns hand/player dependencies and should not add scene nodes to domain protocol.

### Step 5: Run integration regressions

```powershell
& $godot --headless --path . --script res://tests/event_interaction_controller_test.gd
& $godot --headless --path . --script res://tests/event_modal_coordinator_test.gd
& $godot --headless --path . --script res://tests/encounter_resolution_coordinator_test.gd
& $godot --headless --path . --script res://tests/run_flow_coordinator_test.gd
& $godot --headless --path . --script res://tests/game_manager_combat_routing_test.gd
& $godot --headless --editor --path . --quit
```

Expected: all commands exit `0`; final result is not published before the terminal batch is presented and ACKed.

### Step 6: Commit

```powershell
git add scripts/game/event/encounter/encounter_combat_flow_coordinator.gd scripts/game/event/event_interaction_controller.gd scripts/game/event/event_modal_coordinator.gd scripts/game/run/run_flow_coordinator.gd scripts/game/event/encounter/combat_event_view.gd tests/event_interaction_controller_test.gd tests/event_modal_coordinator_test.gd tests/encounter_resolution_coordinator_test.gd tests/run_flow_coordinator_test.gd tests/game_manager_combat_routing_test.gd
git commit -m "refactor: stream encounter combat sessions"
```

---

## Task 12: Remove legacy full replay, harden faults, and run the complete regression suite

**Files**

- Modify: `scripts/combatv2/combat_service.gd`
- Modify: `scripts/game/event/encounter/combat_event_view.gd`
- Modify: `scripts/game/event/event_interaction_controller.gd`
- Modify: `scripts/game/event/event_modal_coordinator.gd`
- Create: `tests/helpers/combat_session_test_fixture.gd`
- Test: `tests/combat_fault_handling_test.gd`
- Test: `tests/combat_session_end_to_end_test.gd`
- Modify tests as required by deleted legacy APIs:
  - `tests/combatv2_service_test.gd`
  - `tests/combat_event_ui_scene_test.gd`
  - `tests/game_manager_combat_routing_test.gd`

**Consumes**

```gdscript
CombatSession.fail(reason: StringName, details: Dictionary = {}) -> CombatEventBatch
EventInteractionController.cancel_combat(reason: StringName) -> void
```

**Produces**

```gdscript
CombatSession.get_fault() -> Dictionary
CombatResult generated only from a terminal session snapshot
No runtime caller of CombatService.resolve_encounter()
No runtime caller of CombatEventView.show_combat(..., result)
```

### Step 1: Write the failing fault-handling test

Create `tests/combat_fault_handling_test.gd`:

```gdscript
extends SceneTree

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_session_test_fixture.gd").new()
    var session: CombatSession = fixture.make_session()
    _ack(session, session.start())

    var bad := CombatIntent.new(999, &"source", &"target", {})
    var batch := session.commit_test_intents([bad])
    assert(batch.kind == CombatEventBatch.Kind.COMBAT_END)
    assert(session.get_phase() == CombatSession.Phase.FAULTED)
    assert(session.get_fault()[&"reason"] == &"unsupported_intent")
    assert(session.advance_one_event() == null)
    quit(0)
```

Expose `commit_test_intents()` only from a test subclass/fixture; do not add it to the production session API.

### Step 2: Write the failing end-to-end scenario test

Create `tests/combat_session_end_to_end_test.gd`:

```gdscript
extends SceneTree

func _init() -> void:
    var fixture := load("res://tests/helpers/combat_session_test_fixture.gd").new()
    var session: CombatSession = fixture.make_trigger_and_operation_session()
    var kinds: Array[int] = []
    var batch := session.start()
    while batch != null:
        kinds.append(batch.kind)
        assert(session.acknowledge_batch(batch.sequence))
        if session.get_phase() == CombatSession.Phase.PLAYER_OPERATION_WINDOW:
            assert(session.submit_command(fixture.make_shield_command()).is_accepted)
            session.close_operation_window()
        batch = session.advance_one_event()

    assert(kinds == [
        CombatEventBatch.Kind.COMBAT_START,
        CombatEventBatch.Kind.CARD_TRIGGER,
        CombatEventBatch.Kind.PLAYER_ATTACK,
        CombatEventBatch.Kind.COMBAT_OPERATION,
        CombatEventBatch.Kind.CARD_TRIGGER,
        CombatEventBatch.Kind.MONSTER_ATTACK,
        CombatEventBatch.Kind.COMBAT_END,
    ])
    assert(session.is_finished())
    assert(session.build_result() != null)
    quit(0)
```

The fixture values must make the exact sequence deterministic and non-lethal until after the monster attack.

### Step 3: Run tests and verify failure

```powershell
& $godot --headless --path . --script res://tests/combat_fault_handling_test.gd
& $godot --headless --path . --script res://tests/combat_session_end_to_end_test.gd
```

Expected: fault conversion and complete event ordering are not yet enforced.

### Step 4: Harden session failure behavior and remove legacy runtime paths

On internal resolution error:

1. Stop accepting commands.
2. Clear pending command/trigger requests.
3. Record a structured fault dictionary.
4. Emit one terminal/fault `COMBAT_END` batch if no batch is already pending.
5. Do not apply additional state mutation.
6. Allow the UI/controller to leave combat safely after presenting the terminal batch.

Search and remove runtime uses:

```powershell
rg "resolve_encounter\(|\.resolve\(player_stats|show_combat\(" scripts scenes
```

Expected after migration: no encounter runtime call computes a complete fight synchronously and no view replays a precomputed `CombatResult`. A narrow compatibility method may remain only if a still-valued isolated service test requires it; annotate it `@deprecated` in prose and ensure no scene/controller references it.

Ensure command rejection is a normal `COMMAND_REJECTED` batch, not a session fault. A stale view target during presentation is a warning and immediate visual completion, not a session fault.

### Step 5: Run the complete combat and integration suite

```powershell
$tests = @(
  'combat_protocol_test.gd',
  'combat_session_state_test.gd',
  'combat_intent_resolver_test.gd',
  'combat_session_test.gd',
  'combat_attack_order_test.gd',
  'combat_trigger_queue_test.gd',
  'combat_operation_resolver_test.gd',
  'combat_pending_request_revalidation_test.gd',
  'combat_retreat_operation_test.gd',
  'combat_gold_shield_operation_test.gd',
  'combat_speed_controller_test.gd',
  'combat_scheduler_test.gd',
  'combat_operation_drag_adapter_test.gd',
  'combat_presentation_coordinator_test.gd',
  'combat_fault_handling_test.gd',
  'combat_session_end_to_end_test.gd',
  'combatv2_service_test.gd',
  'combat_effect_pipeline_test.gd',
  'combatv2_card_rule_test.gd',
  'ribwood_combat_balance_test.gd',
  'event_interaction_controller_test.gd',
  'event_modal_coordinator_test.gd',
  'combat_event_ui_scene_test.gd',
  'game_manager_combat_routing_test.gd',
  'encounter_resolution_coordinator_test.gd',
  'run_flow_coordinator_test.gd',
  'dragger_layer_test.gd',
  'drag_layer_retraction_test.gd',
  'hand_zone_drag_cancel_test.gd',
  'card_chain_coordinator_test.gd',
  'board_zone_test.gd',
  'board_scene_composition_test.gd'
)
$godot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
foreach ($test in $tests) {
  & $godot --headless --path . --script ("res://tests/" + $test)
  if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
}
& $godot --headless --editor --path . --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import/compile check failed' }
```

Expected: every test and the final import/compile check exit `0`.

### Step 6: Inspect architecture invariants

```powershell
rg "resolve_encounter\(|show_combat\(" scripts scenes
rg "DAMAGE_MONSTER|DAMAGE_CARD" scripts/combatv2/session
rg "combat_speed|speed_multiplier" scripts/combatv2 scripts/game/event
rg "CUT_CHAIN_FROM_TARGET|ADD_CARD_SHIELD" scripts/combatv2
```

Confirm manually:

- Player and monster attacks are created in separate request handlers and separate batches.
- No operation drag adapter performs domain mutation.
- Preview DTO exposes target presentation only.
- Every accepted operation is revalidated at dequeue time.
- ACK is required before another batch is committed.
- Speed affects settlement delay, presentation calls, and operation-window real duration.
- Active drag blocks advancement.
- Final settlement starts only after terminal batch ACK.

### Step 7: Commit

```powershell
git add scripts/combatv2/combat_service.gd scripts/game/event/encounter/combat_event_view.gd scripts/game/event/event_interaction_controller.gd scripts/game/event/event_modal_coordinator.gd tests/helpers/combat_session_test_fixture.gd tests/combat_fault_handling_test.gd tests/combat_session_end_to_end_test.gd tests/combatv2_service_test.gd tests/combat_event_ui_scene_test.gd tests/game_manager_combat_routing_test.gd
git commit -m "test: complete stateful combat migration"
```

---

## Final acceptance checklist

### Protocol and sequencing

- [ ] `CombatSession` is the only authoritative combat state machine.
- [ ] `advance_one_event()` commits at most one major atomic behavior.
- [ ] Batches are immutable copies with monotonically increasing sequence IDs.
- [ ] The next batch cannot commit before the current batch is ACKed.
- [ ] Player and monster attacks use separate phases, intent sets, and batches.
- [ ] A lethal player attack prevents monster attack creation.
- [ ] Trigger requests explicitly represent combat start, attack completion, trigger completion, and front-card depletion.

### Player operations

- [ ] Operation cards use shared definition, target, cost, disposition, effect, command, and resolver types.
- [ ] Commands affect only future uncommitted requests.
- [ ] Submission order is deterministic; dequeue-time revalidation is mandatory.
- [ ] Invalid fixed targets reject without automatic retargeting.
- [ ] Rejected operations cause no partial mutation or card consumption.
- [ ] Retreat cuts from the selected card toward the head, consumes itself, skips remaining combat, and enhances the monster once.
- [ ] Gold-for-shield spends and updates shield atomically.
- [ ] Preview exposes target/validity/highlight/reason only.

### Presentation and timing

- [ ] Board card IDs map domain events to the correct `CardEntity`.
- [ ] Point, shield, and trigger animation hooks exist even if animation bodies are minimal.
- [ ] Missing presentation targets cannot deadlock ACK.
- [ ] The setting is named “combat speed” / “战斗速度”.
- [ ] Live speed changes preserve elapsed progress and rescale remaining real time.
- [ ] Settlement delay, presentation animation requests, and operation-window duration use combat speed.
- [ ] Active dragging holds session advancement.

### Integration and safety

- [ ] Domain protocol contains no scene `Node` references.
- [ ] Encounter controller emits batches incrementally and emits the final result once.
- [ ] Final result/settlement occurs only after terminal presentation ACK.
- [ ] No runtime path replays a precomputed full combat result.
- [ ] Unrelated user working-tree changes remain untouched and unstaged.
- [ ] Complete combat, drag, board, event, and run-flow regressions pass.
