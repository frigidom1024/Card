# Configurable Encounter Reward Drops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make monster and Boss encounter rewards inspector-configurable as independently rolled gold and card drops that are granted only after a confirmed victory.

**Architecture:** `EncounterEventContent` becomes the single run-time reward source through an exported array of `EncounterDropEntry` resources. A pure `EncounterRewardResolver` produces an `EncounterRewardResult` from that data and an injected RNG; `EncounterResolutionCoordinator` applies the result to `PlayerData` and `RunCardService` after combat settlement. The UI and combat routes are unchanged; `GameManager` remains the composition root that supplies run state, a player-state refresh callback, and a randomized reward RNG.

**Tech Stack:** Godot 4.7, GDScript, `.tres` resources, headless SceneTree tests.

## Global Constraints

- Work only in `D:/project/MonoCard/mono-card/.worktrees/codex-encounter-rewards` on branch `codex/encounter-rewards`; do not modify the main worktree’s uncommitted files.
- Reward data lives on `EncounterEventContent.drop_entries`; `MonsterEventContent` and `BossEventContent` inherit it without separate implementations.
- Each entry has an independent inclusive chance in `0.0..1.0`; one victory can award all successful entries.
- Resolve and mutate drops only for `CombatResult.Outcome.VICTORY`; `RETREAT` and `DEFEAT` must leave gold and card ownership unchanged.
- Encounter-reward cards must use a dedicated temporary-overflow grant method so a full normal hand never destroys a won card, and the configured normal hand capacity must be restored immediately afterward.
- Keep `MobData.gold_reward` and `MobData.card_rewards` untouched in this increment; existing legacy data remains compatible, but live reward application reads only encounter content.
- Do not add a reward-selection modal, change event triggering, alter Boss cleanup, alter faith, or alter exploration spawning.
- Use `D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe` for every headless test command in this workspace.

---

## File Structure

| Path | Responsibility |
| --- | --- |
| `scripts/game/event/encounter/encounter_drop_entry.gd` | Inspector-facing drop resource, entry kind enum, and data validation. |
| `scripts/game/event/encounter/encounter_reward_result.gd` | Small value object carrying resolved gold and ordered cards. |
| `scripts/game/event/encounter/encounter_reward_resolver.gd` | Stateless probability and validation logic with no run-state mutation. |
| `scripts/game/event/encounter/encounter_event_content.gd` | Adds the designer-configurable `drop_entries` array shared by monster and Boss content. |
| `scripts/game/run/run_card_service.gd` | Safely grants a newly won card while temporarily permitting hand overflow. |
| `scripts/game/event/encounter/encounter_resolution_coordinator.gd` | Resolves rewards in the confirmed-victory branch and applies them to the run. |
| `scripts/game_manager.gd` | Owns and injects the randomized encounter-reward RNG and current `PlayerData`. |
| `tests/encounter_reward_resolver_test.gd` | Focused behavior tests for resource validation and deterministic reward rolls. |
| `tests/run_card_service_test.gd` | Verifies a new rewarded card remains owned and in hand when the hand is normally full. |
| `tests/encounter_resolution_coordinator_test.gd` | Verifies run mutation, outcome gating, one HUD callback, full-hand behavior, and Boss reuse. |
| `tests/ribwood_echo_data_test.gd` | Verifies Ribwood encounter content carries the intended independent drop configuration. |
| `data/levels/ribwood/event_content/ribwood_marrow_rat_content.tres` | Configures the rat’s 8-gold guarantee and 20% low-power card roll. |
| `data/levels/ribwood/event_content/ribwood_fallen_rib_wolf_content.tres` | Configures the wolf’s 12-gold guarantee and 35% defensive card roll. |
| `data/levels/ribwood/event_content/ribwood_white_horn_hart_boss_content.tres` | Deliberately keeps the Boss drop list empty so its dedicated clear reward remains unique. |

## Task 1: Drop Resource and Pure Resolver

**Files:**
- Create: `scripts/game/event/encounter/encounter_drop_entry.gd`
- Create: `scripts/game/event/encounter/encounter_reward_result.gd`
- Create: `scripts/game/event/encounter/encounter_reward_resolver.gd`
- Modify: `scripts/game/event/encounter/encounter_event_content.gd:1-10`
- Create: `tests/encounter_reward_resolver_test.gd`

**Interfaces:**
- Produces: `EncounterDropEntry.Kind { GOLD, CARD }`, `EncounterDropEntry.validate() -> PackedStringArray`, `EncounterRewardResult.gold: int`, `EncounterRewardResult.cards: Array[CardData]`, and `EncounterRewardResolver.resolve(content: EncounterEventContent, rng: RandomNumberGenerator) -> EncounterRewardResult`.
- Consumes: `EncounterEventContent.drop_entries: Array[EncounterDropEntry]` from encounter resources and an RNG explicitly seeded by tests.

- [ ] **Step 1: Write the failing resolver tests**

Create `tests/encounter_reward_resolver_test.gd` as a headless `SceneTree` test. Add cases with literal expected values:

```gdscript
func _test_guaranteed_entries_award_gold_and_card_in_order() -> void:
    var card := CardData.new()
    card.card_name = "Resolver Card"
    var content := MonsterEventContent.new()
    content.drop_entries = [_gold_drop(1.0, 8), _card_drop(1.0, card)]
    var rng := RandomNumberGenerator.new()
    rng.seed = 11

    var result := EncounterRewardResolver.new().resolve(content, rng)

    _expect(result.gold == 8, "a successful gold entry adds its configured amount")
    _expect(result.cards == [card], "a successful card entry preserves configured card order")
```

Add independent cases proving a `0.0` gold/card entry awards nothing, two `1.0` gold entries sum to `13`, an invalid negative gold entry is skipped without suppressing a later valid entry, a missing card entry is skipped, and `validate()` rejects chance `-0.1`, chance `1.1`, gold `0`, and a null card.

- [ ] **Step 2: Run the new test to verify RED**

Run:

```powershell
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/encounter_reward_resolver_test.gd
```

Expected: the test fails because `EncounterDropEntry` and `EncounterRewardResolver` do not yet exist.

- [ ] **Step 3: Add the minimal resource and resolver implementation**

Create the drop resource with concrete inspector fields and defensive validation:

```gdscript
class_name EncounterDropEntry
extends Resource

enum Kind { GOLD, CARD }

@export var kind: Kind = Kind.GOLD
@export_range(0.0, 1.0, 0.01) var chance := 1.0
@export var gold_amount := 0
@export var card_data: CardData

func validate() -> PackedStringArray:
    var errors := PackedStringArray()
    if chance < 0.0 or chance > 1.0:
        errors.append("chance must be between 0.0 and 1.0")
    if kind == Kind.GOLD and gold_amount <= 0:
        errors.append("gold entries require gold_amount greater than 0")
    if kind == Kind.CARD and card_data == null:
        errors.append("card entries require card_data")
    return errors
```

Create `EncounterRewardResult` with `var gold := 0` and `var cards: Array[CardData] = []`. Create the resolver so it returns an empty result for null content/RNG, skips null or invalid entries, uses `if rng.randf() >= entry.chance: continue`, accumulates gold, and appends valid cards. Add this exported field to `EncounterEventContent`:

```gdscript
@export var drop_entries: Array[EncounterDropEntry] = []
```

Do not mutate player data, hand state, board state, or event state in any of these three new classes.

- [ ] **Step 4: Run the focused test to verify GREEN**

Run:

```powershell
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/encounter_reward_resolver_test.gd
```

Expected: exit code `0`; 0% entries never award, 100% entries always award, invalid data is skipped, and multiple valid entries resolve independently.

- [ ] **Step 5: Check formatting and commit the pure reward layer**

Run:

```powershell
gdformat --check scripts/game/event/encounter/encounter_drop_entry.gd scripts/game/event/encounter/encounter_reward_result.gd scripts/game/event/encounter/encounter_reward_resolver.gd scripts/game/event/encounter/encounter_event_content.gd tests/encounter_reward_resolver_test.gd
git diff --check
git add scripts/game/event/encounter/encounter_drop_entry.gd scripts/game/event/encounter/encounter_reward_result.gd scripts/game/event/encounter/encounter_reward_resolver.gd scripts/game/event/encounter/encounter_event_content.gd tests/encounter_reward_resolver_test.gd
git commit -m "feat(encounter): resolve configurable reward drops"
```

Expected: formatting and whitespace checks pass; the commit contains the resource model, pure resolver, and direct behavior tests.

## Task 2: Safe Card Grant and Confirmed-Victory Integration

**Files:**
- Modify: `scripts/game/run/run_card_service.gd:42-73`
- Modify: `scripts/game/event/encounter/encounter_resolution_coordinator.gd:10-91`
- Modify: `scripts/game_manager.gd:42,107-127,217-230`
- Modify: `tests/run_card_service_test.gd:17-110`
- Modify: `tests/encounter_resolution_coordinator_test.gd:17-225`

**Interfaces:**
- Consumes: `EncounterRewardResolver.resolve(content, rng)`, `PlayerData.gold`, and `RunCardService.grant_to_hand_temporarily(card_data)`.
- Produces: `RunCardService.grant_to_hand_temporarily(card_data: CardData) -> bool` and the expanded coordinator configuration signature:

```gdscript
func configure(
    board: Board,
    player_stats: CombatStats,
    player_data: PlayerData,
    card_service: RunCardService,
    exploration: ExplorationCoordinator,
    on_player_state_changed: Callable,
    reward_rng: RandomNumberGenerator
) -> bool
```

- [ ] **Step 1: Write failing full-hand card-grant and settlement tests**

In `tests/run_card_service_test.gd`, add a test that fills the hand, stores `original_max_hand_size`, calls the wished-for API, and asserts the new card is both tracked and in hand while the configured limit is restored:

```gdscript
_expect(service.grant_to_hand_temporarily(RevivalDeck.starter_cards[0]), "reward grant accepts a card when the normal hand is full")
_expect(service.get_entities().size() == existing_count + 1, "reward grant owns the new card")
_expect(service.get_entities().back() in service.hand_area.cards, "reward grant keeps the new card in hand")
_expect(service.hand_area.max_hand_size == original_max_hand_size, "reward grant restores the configured hand limit")
```

In `tests/encounter_resolution_coordinator_test.gd`, add a `PlayerData` and seeded `RandomNumberGenerator` to the fixture. Add a monster victory with `[gold 8 at 1.0, card at 1.0]`, assert `player_data.gold` changes from `30` to `38`, the new card remains in a full hand, and the state-change callback count is exactly one. Add a RETREAT fixture and a DEFEAT fixture with the same guaranteed entries and assert each leaves `gold`, owned-card count, and hand-card count unchanged. Extend the existing Boss victory test with a configured gold entry and assert it grants gold before the event is removed.

- [ ] **Step 2: Run the changed tests to verify RED**

Run:

```powershell
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/run_card_service_test.gd
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/encounter_resolution_coordinator_test.gd
```

Expected: the service test fails because the temporary-overflow new-grant method is missing; the coordinator test fails because it has no `PlayerData`/RNG dependency or reward application branch.

- [ ] **Step 3: Implement the smallest run-state integration**

Add this method to `RunCardService`; it must restore capacity even when entity creation fails:

```gdscript
func grant_to_hand_temporarily(card_data: CardData) -> bool:
    if not _is_configured() or card_data == null:
        return false
    var previous_max_hand_size := hand_area.max_hand_size
    if hand_area.is_full():
        hand_area.max_hand_size = hand_area.cards.size() + 1
    var granted := grant_to_hand(card_data)
    hand_area.max_hand_size = previous_max_hand_size
    return granted
```

Extend `EncounterResolutionCoordinator` with `_player_data`, `_reward_rng`, and a private `_reward_resolver := EncounterRewardResolver.new()`. Reject null `player_data` or `reward_rng` in `configure`. In the `VICTORY` branch, update the combat snapshots, call a private `_apply_victory_rewards(instance)`, then execute the existing resolve-and-Boss-removal or event-refresh behavior. `_apply_victory_rewards` must resolve `instance.data.content as EncounterEventContent`, add `result.gold` to `_player_data.gold`, and call `grant_to_hand_temporarily` for each card; a failed card grant only calls `push_error` and never rolls back victory or gold.

Move the existing `_on_player_state_changed.call()` out of `_apply_player_combat_state()` and call it once at the end of every successful `apply()` outcome branch. This ensures the crest/HUD sees both combat HP and reward gold in a victory refresh while preserving refreshes for RETREAT and DEFEAT.

In `GameManager`, add `_encounter_reward_rng := RandomNumberGenerator.new()`, call `_encounter_reward_rng.randomize()` after successful run-state initialization, and pass `player_data` and `_encounter_reward_rng` into `_encounter_resolution.configure(...)`.

- [ ] **Step 4: Run focused integration tests to verify GREEN**

Run:

```powershell
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/run_card_service_test.gd
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/encounter_resolution_coordinator_test.gd
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/game_manager_player_hud_test.gd
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/game_manager_architecture_test.gd
```

Expected: exit code `0`; all ordinary, Boss, full-hand, and non-victory outcomes retain their asserted behavior.

- [ ] **Step 5: Check formatting and commit integration**

Run:

```powershell
gdformat --check scripts/game/run/run_card_service.gd scripts/game/event/encounter/encounter_resolution_coordinator.gd scripts/game_manager.gd tests/run_card_service_test.gd tests/encounter_resolution_coordinator_test.gd
git diff --check
git add scripts/game/run/run_card_service.gd scripts/game/event/encounter/encounter_resolution_coordinator.gd scripts/game_manager.gd tests/run_card_service_test.gd tests/encounter_resolution_coordinator_test.gd
git commit -m "feat(encounter): grant rewards after victory"
```

Expected: every test asserted above is green and this commit contains only reward application, dependency injection, safe card ownership, and direct tests.

## Task 3: Configure Ribwood Drop Data

**Files:**
- Modify: `data/levels/ribwood/event_content/ribwood_marrow_rat_content.tres`
- Modify: `data/levels/ribwood/event_content/ribwood_fallen_rib_wolf_content.tres`
- Modify: `data/levels/ribwood/event_content/ribwood_white_horn_hart_boss_content.tres`
- Modify: `tests/ribwood_echo_data_test.gd:1-58`

**Interfaces:**
- Consumes: `EncounterEventContent.drop_entries` and existing Ribwood card resources.
- Produces: Rat content with `GOLD(1.0, 8)` plus `CARD(0.20, ribwood_old_tinder.tres)`; wolf content with `GOLD(1.0, 12)` plus `CARD(0.35, ribwood_folded_rib_shield.tres)`; Boss content with `[]`.

- [ ] **Step 1: Write failing Ribwood encounter-content assertions**

Replace the reward checks in `tests/ribwood_echo_data_test.gd` that inspect `Rat.gold_reward` and `Wolf.gold_reward`. Preload the three encounter-content resources and add assertions that inspect their `drop_entries` directly:

```gdscript
_expect(RatContent.drop_entries.size() == 2, "marrow rat has gold and card drop entries")
_expect(RatContent.drop_entries[0].kind == EncounterDropEntry.Kind.GOLD, "marrow rat first drop is gold")
_expect(RatContent.drop_entries[0].chance == 1.0 and RatContent.drop_entries[0].gold_amount == 8, "marrow rat guarantees 8 gold")
_expect(RatContent.drop_entries[1].kind == EncounterDropEntry.Kind.CARD, "marrow rat second drop is a card")
_expect(RatContent.drop_entries[1].chance == 0.20 and RatContent.drop_entries[1].card_data.card_name == "旧火绒", "marrow rat has a 20% old tinder drop")
```

Add equivalent literal checks for wolf `12`, `0.35`, and `折叠肋盾`; assert `HartContent.drop_entries.is_empty()`.

- [ ] **Step 2: Run the data test to verify RED**

Run:

```powershell
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/ribwood_echo_data_test.gd
```

Expected: the content data has no drop entries yet, so the new assertions fail.

- [ ] **Step 3: Author the three content resources**

In the rat and wolf content `.tres` files, add external resources for `encounter_drop_entry.gd` and the stated card resource. Define two inline `SubResource` drop entries in each file, preserving sequence: guaranteed gold first and optional card second. Example rat shape:

```ini
[sub_resource type="Resource" id="Drop_gold"]
script = ExtResource("drop_entry")
kind = 0
chance = 1.0
gold_amount = 8

[sub_resource type="Resource" id="Drop_card"]
script = ExtResource("drop_entry")
kind = 1
chance = 0.2
card_data = ExtResource("old_tinder")

[resource]
script = ExtResource("content")
mob = ExtResource("mob")
count = 1
drop_entries = Array[ExtResource("drop_entry")]([SubResource("Drop_gold"), SubResource("Drop_card")])
```

Use `gold_amount = 12`, `chance = 0.35`, and `ribwood_folded_rib_shield.tres` for the wolf. Leave the Boss resource without a `drop_entries` property, so its exported default stays empty. Do not change combat values or the legacy reward values serialized on `MobData`.

- [ ] **Step 4: Run data, gameplay, and resource tests to verify GREEN**

Run:

```powershell
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/ribwood_echo_data_test.gd
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/ribwood_event_lib_test.gd
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/ribwood_card_data_test.gd
& 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/ribwood_combat_balance_test.gd
```

Expected: exit code `0`; level resources load and the revised reward assertions pass without changing the original combat balance.

- [ ] **Step 5: Editor scan, full-suite verification, and commit data**

Run an editor resource scan followed by every headless test:

```powershell
$godot = 'D:/InstallPath/godot/Godot_v4.7-stable_win64_console.exe'
& $godot --editor --headless --path . --quit
$failed = @()
Get-ChildItem tests -Filter '*.gd' | Sort-Object Name | ForEach-Object {
    & $godot --headless --path . --script ("res://tests/{0}" -f $_.Name)
    if ($LASTEXITCODE -ne 0) { $failed += $_.Name }
}
if ($failed.Count -gt 0) { throw ("Failed tests: " + ($failed -join ', ')) }
git diff --check
git add data/levels/ribwood/event_content/ribwood_marrow_rat_content.tres data/levels/ribwood/event_content/ribwood_fallen_rib_wolf_content.tres data/levels/ribwood/event_content/ribwood_white_horn_hart_boss_content.tres tests/ribwood_echo_data_test.gd
git commit -m "data(ribwood): configure echo reward drops"
```

Expected: the editor scan creates/updates Godot import metadata only as needed; all test scripts exit `0`; the commit contains only Ribwood reward resources and their executable data checks.

## Plan Self-Review

### Spec coverage

| Approved requirement | Planned task |
| --- | --- |
| Per-encounter configurable gold/card entries | Task 1 resource plus `EncounterEventContent` export. |
| Independent chance per entry and combined awards | Task 1 resolver behavior tests. |
| Both normal residuals and Bosses use the same mechanism | Task 2 Boss integration assertion. |
| Victory-only rewards | Task 2 RETREAT/DEFEAT tests and outcome branch. |
| Full hand cannot lose rewarded card | Task 2 temporary-overflow service test and implementation. |
| Player gold is stored on `PlayerData` and HUD refreshes | Task 2 explicit dependency injection and one callback after mutation. |
| Ribwood rat/wolf/Boss initial configuration | Task 3 `.tres` resources and level-data tests. |
| Preserve existing event/Boss/exploration interaction paths | Global constraints and Task 2 reuse of current resolve/remove/refresh routes. |

### Type consistency

- `EncounterDropEntry.validate()` is the only validation API used by the resolver and data tests.
- `EncounterRewardResolver.resolve(content, rng)` is the only reward calculation API used by the coordinator.
- `RunCardService.grant_to_hand_temporarily(card_data)` is the only new-card full-hand API used by the coordinator.
- `EncounterResolutionCoordinator.configure(...)` receives both run-level `PlayerData` and an injected RNG from `GameManager` and from test fixtures.

### Placeholder scan

The plan contains no unresolved implementation markers. Every code step names exact files, APIs, commands, asserted behaviors, and commit boundaries.