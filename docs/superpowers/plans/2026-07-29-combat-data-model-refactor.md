# Combat Data Model Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give players and monsters one shared combat-stat API while keeping each unit's base stats inline in its own definition resource and isolating every encounter's mutable state.

**Architecture:** `CombatStatsData` is a static `Resource` embedded in `MobData` and `PlayerData`. `CombatStats` is a runtime `RefCounted` copy used by unit instances. `MobInstance` owns monster-specific encounter state, so `MobData` never changes during play. The existing event-directory migration is preserved rather than reversed.

**Tech Stack:** Godot 4.7, GDScript, `.tres` resources, headless Godot validation, PowerShell reference checks.

## Global Constraints

- Do not create one external `*_stats.tres` file per monster.
- Static `.tres` data must never contain current HP, temporary defense, or event-local action progress.
- Do not revert, delete, or stage unrelated existing worktree changes.
- Preserve the current `data/event/` and `scripts/game/event/` migration layout; directory renaming is outside this refactor.
- Repair every stale `res://scripts/card_data.gd` reference to `res://scripts/card/card_data.gd`.
- Do not add third-party dependencies or a test framework.

---

## Target File Structure

```text
scripts/
  combat/
    combat_stats_data.gd       # Static base values, Resource
    combat_stats.gd            # Mutable combat values, RefCounted
  player/
    player_data.gd             # Player static definition, Resource
  game/event/
    mob_data.gd                # Monster static definition
    mob_instance.gd            # Monster encounter state

data/
  player/
    player_data.tres           # One player definition with inline stats
  event/mobs/
    wolf_mob.tres              # Valid monster definition

tests/
  combat_model_test.gd         # Headless, dependency-free regression test
```

## Task 1: Introduce the shared combat-stat definition and runtime API

**Files:**
- Create: `scripts/combat/combat_stats_data.gd`
- Create: `scripts/combat/combat_stats.gd`
- Create: `tests/combat_model_test.gd`
- Remove after migration: `scripts/character_stats.gd`
- Remove after migration: `scripts/character_stats.gd.uid`
- Remove after migration: `scripts/character_stats_instance.gd`
- Remove after migration: `scripts/character_stats_instance.gd.uid`

**Interfaces:**
- Produces `CombatStatsData` with exported `max_hp: int`, `attack: int`, and `defense: int`.
- Produces `CombatStats.from_data(data: CombatStatsData) -> CombatStats`.
- Produces `CombatStats.take_damage(amount: int) -> int`, `heal(amount: int) -> int`, `add_defense(amount: int) -> void`, `modify_attack(amount: int) -> void`, and `is_alive() -> bool`.

- [ ] **Step 1: Write the failing headless regression test**

Create `tests/combat_model_test.gd`:

```gdscript
extends SceneTree

const CombatStatsDataScript = preload("res://scripts/combat/combat_stats_data.gd")
const CombatStatsScript = preload("res://scripts/combat/combat_stats.gd")

func _init() -> void:
    var data = CombatStatsDataScript.new()
    data.max_hp = 10
    data.attack = 3
    data.defense = 2

    var stats = CombatStatsScript.from_data(data)
    _expect(stats.hp == 10, "new runtime stats start at maximum HP")
    _expect(stats.attack == 3, "runtime attack copies base attack")
    _expect(stats.take_damage(5) == 3, "defense absorbs two damage")
    _expect(stats.hp == 7, "only unabsorbed damage reduces HP")
    stats.heal(99)
    _expect(stats.hp == 10, "healing cannot exceed maximum HP")
    stats.add_defense(4)
    stats.modify_attack(-1)
    _expect(stats.defense == 4, "damage consumes existing defense before new defense is added")
    _expect(stats.attack == 2, "attack modifiers use the shared runtime API")
    quit(0)

func _expect(condition: bool, message: String) -> void:
    if not condition:
        push_error(message)
        quit(1)
```

- [ ] **Step 2: Run the test and verify it fails because the scripts do not exist**

Run:

```powershell
Godot --headless --path . --script res://tests/combat_model_test.gd
```

Expected: non-zero exit with a preload error for `scripts/combat/combat_stats_data.gd`.

- [ ] **Step 3: Implement static and runtime combat stats**

Create `scripts/combat/combat_stats_data.gd`:

```gdscript
class_name CombatStatsData
extends Resource

@export_range(1, 9999) var max_hp: int = 1
@export var attack: int = 0
@export var defense: int = 0
```

Create `scripts/combat/combat_stats.gd`:

```gdscript
class_name CombatStats
extends RefCounted

var max_hp: int
var hp: int
var attack: int
var defense: int

static func from_data(data: CombatStatsData) -> CombatStats:
    var stats := CombatStats.new()
    stats.max_hp = data.max_hp
    stats.hp = data.max_hp
    stats.attack = data.attack
    stats.defense = data.defense
    return stats

func take_damage(amount: int) -> int:
    var incoming := max(amount, 0)
    var absorbed := min(defense, incoming)
    defense -= absorbed
    var applied := incoming - absorbed
    hp = max(hp - applied, 0)
    return applied

func heal(amount: int) -> int:
    var before := hp
    hp = min(hp + max(amount, 0), max_hp)
    return hp - before

func add_defense(amount: int) -> void:
    defense = max(defense + amount, 0)

func modify_attack(amount: int) -> void:
    attack = max(attack + amount, 0)

func is_alive() -> bool:
    return hp > 0
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```powershell
Godot --headless --path . --script res://tests/combat_model_test.gd
```

Expected: exit code `0`.

- [ ] **Step 5: Remove obsolete character-stat scripts and commit this unit of work**

Run:

```powershell
Remove-Item -LiteralPath scripts/character_stats.gd,scripts/character_stats.gd.uid,scripts/character_stats_instance.gd,scripts/character_stats_instance.gd.uid
# Stage only the files listed in this task, then commit with:
git commit -m "feat: add shared combat stats model"
```

Expected: the project has exactly one static and one runtime shared combat-stat type.

## Task 2: Separate monster definitions from per-encounter state

**Files:**
- Modify: `scripts/game/event/mob_data.gd`
- Create: `scripts/game/event/mob_instance.gd`
- Modify: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes `CombatStatsData`, `CombatStats`, `MobAction`, and `CardData` from Task 1.
- Produces `MobData.create_instance() -> MobInstance`.
- Produces `MobInstance.get_next_action() -> MobAction`, `take_damage(amount: int) -> int`, and `is_alive() -> bool`.

- [ ] **Step 1: Extend the failing test for independent monster encounters**

Append to `_init()` before `quit(0)` in `tests/combat_model_test.gd`:

```gdscript
var mob_data = preload("res://scripts/game/event/mob_data.gd").new()
mob_data.base_stats = data
var first = mob_data.create_instance()
var second = mob_data.create_instance()
first.take_damage(10)
_expect(not first.is_alive(), "first encounter can be defeated")
_expect(second.is_alive(), "second encounter has independent runtime HP")
_expect(second.stats.hp == 10, "definition resources are not mutated by encounters")
```

- [ ] **Step 2: Run the test and verify it fails because `create_instance` is unavailable**

Run:

```powershell
Godot --headless --path . --script res://tests/combat_model_test.gd
```

Expected: non-zero exit reporting that `MobData` has no `create_instance` method.

- [ ] **Step 3: Replace mutable fields in `MobData` and implement `MobInstance`**

Replace `scripts/game/event/mob_data.gd` with:

```gdscript
class_name MobData
extends Resource

@export var mob_name: String = ""
@export var base_stats: CombatStatsData
@export var actions: Array[MobAction] = []
@export var gold_reward: int = 0
@export var card_rewards: Array[CardData] = []

func create_instance() -> MobInstance:
    return MobInstance.new(self)
```

Create `scripts/game/event/mob_instance.gd`:

```gdscript
class_name MobInstance
extends RefCounted

var data: MobData
var stats: CombatStats
var action_index: int = 0

func _init(mob_data: MobData) -> void:
    data = mob_data
    if data.base_stats:
        stats = CombatStats.from_data(data.base_stats)
    else:
        push_error("MobData[%s] is missing base_stats" % data.mob_name)

func get_next_action() -> MobAction:
    if data.actions.is_empty():
        return null
    var action := data.actions[action_index]
    action_index = (action_index + 1) % data.actions.size()
    return action

func take_damage(amount: int) -> int:
    return stats.take_damage(amount) if stats else 0

func is_alive() -> bool:
    return stats != null and stats.is_alive()
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```powershell
Godot --headless --path . --script res://tests/combat_model_test.gd
```

Expected: exit code `0`; the independent-encounter assertions pass.

- [ ] **Step 5: Commit this unit of work**

Stage only `scripts/game/event/mob_data.gd`, `scripts/game/event/mob_instance.gd`, their generated `.uid` files, and `tests/combat_model_test.gd`; then commit:

```powershell
git commit -m "feat: separate mob encounter state from data"
```

## Task 3: Give the player the same static definition and runtime API

**Files:**
- Create: `scripts/player/player_data.gd`
- Create: `data/player/player_data.tres`
- Modify: `scripts/game_manager.gd`
- Modify: `scenes/game/game_manager.tscn`
- Modify: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes `CombatStatsData` and `CombatStats` from Task 1.
- Produces `PlayerData.base_stats: CombatStatsData`.
- Produces `GameManager.player_stats: CombatStats` initialized from its exported `player_data`.

- [ ] **Step 1: Extend the failing test for player and monster API parity**

Append to `_init()` before `quit(0)` in `tests/combat_model_test.gd`:

```gdscript
var player_data = preload("res://scripts/player/player_data.gd").new()
player_data.base_stats = data
var player_stats = CombatStatsScript.from_data(player_data.base_stats)
_expect(player_stats.take_damage(2) == 0, "player stats use the same defense rule as monsters")
_expect(player_stats.is_alive(), "player stats use the same alive-state API as monsters")
```

- [ ] **Step 2: Run the test and verify it fails because `PlayerData` does not exist**

Run:

```powershell
Godot --headless --path . --script res://tests/combat_model_test.gd
```

Expected: non-zero exit with a preload error for `scripts/player/player_data.gd`.

- [ ] **Step 3: Implement player static data and initialize runtime player stats**

Create `scripts/player/player_data.gd`:

```gdscript
class_name PlayerData
extends Resource

@export var player_name: String = "Player"
@export var base_stats: CombatStatsData
```

Create `data/player/player_data.tres` with an inline `CombatStatsData` sub-resource:

```text
[gd_resource type="Resource" script_class="PlayerData" format=3]

[ext_resource type="Script" path="res://scripts/player/player_data.gd" id="1_player"]
[ext_resource type="Script" path="res://scripts/combat/combat_stats_data.gd" id="2_stats"]

[sub_resource type="Resource" id="CombatStatsData_player"]
script = ExtResource("2_stats")
max_hp = 20
attack = 0
defense = 0

[resource]
script = ExtResource("1_player")
player_name = "Player"
base_stats = SubResource("CombatStatsData_player")
```

In `scripts/game_manager.gd`, replace the unused `character_stats` field with:

```gdscript
@export var player_data: PlayerData
var player_stats: CombatStats
```

At the beginning of `_ready()`, before card initialization, add:

```gdscript
if player_data and player_data.base_stats:
    player_stats = CombatStats.from_data(player_data.base_stats)
else:
    push_error("GameManager is missing PlayerData.base_stats")
```

In `scenes/game/game_manager.tscn`, add an external resource for `res://data/player/player_data.tres`, then assign it on the `GameManager` node:

```text
player_data = ExtResource("<player-data-id>")
```

Use Godot to generate stable resource IDs when available; otherwise use a unique local ext-resource ID consistently within this scene.

- [ ] **Step 4: Run the test and verify it passes**

Run:

```powershell
Godot --headless --path . --script res://tests/combat_model_test.gd
```

Expected: exit code `0`; player and monster use the same damage and alive-state behavior.

- [ ] **Step 5: Commit this unit of work**

Stage only the Task 3 files and generated `.uid` files, then commit:

```powershell
git commit -m "feat: initialize player with shared combat stats"
```

## Task 4: Repair content resources and card script references

**Files:**
- Move: `data/event/mobs/new_resource.tres` → `data/event/mobs/wolf_mob.tres`
- Modify: `data/event/mobs/wolf_mob.tres`
- Modify: `data/event/content/event_monster_content.tres`
- Modify: `data/cards/*.tres` that contain `res://scripts/card_data.gd`
- Modify: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes valid `MobData` and `CombatStatsData` from Tasks 1–2.
- Produces a loadable `wolf_mob.tres` with an inline `CombatStatsData` resource.
- Produces card definitions whose script path is `res://scripts/card/card_data.gd`.

- [ ] **Step 1: Extend the test to load real content resources**

Append to `_init()` before `quit(0)` in `tests/combat_model_test.gd`:

```gdscript
var wolf = load("res://data/event/mobs/wolf_mob.tres") as MobData
_expect(wolf != null, "wolf resource loads as MobData")
_expect(wolf.base_stats != null, "wolf resource includes inline base stats")
_expect(wolf.create_instance().is_alive(), "loaded wolf creates a valid encounter")
var card = load("res://data/cards/AllThingsRevival.tres") as CardData
_expect(card != null and card.card_id == 28, "migrated card data still loads")
```

- [ ] **Step 2: Run the test and verify it fails because the wolf resource and stale card paths are invalid**

Run:

```powershell
Godot --headless --path . --script res://tests/combat_model_test.gd
```

Expected: non-zero exit with missing `wolf_mob.tres` and/or invalid card-script resource diagnostics.

- [ ] **Step 3: Create valid inline monster data and repair paths**

Move the existing monster resource only after verifying the source exists:

```powershell
Test-Path data/event/mobs/new_resource.tres
Move-Item -LiteralPath data/event/mobs/new_resource.tres -Destination data/event/mobs/wolf_mob.tres
```

Replace the moved file contents with:

```text
[gd_resource type="Resource" script_class="MobData" format=3]

[ext_resource type="Script" path="res://scripts/game/event/mob_data.gd" id="1_mob"]
[ext_resource type="Script" path="res://scripts/combat/combat_stats_data.gd" id="2_stats"]

[sub_resource type="Resource" id="CombatStatsData_wolf"]
script = ExtResource("2_stats")
max_hp = 12
attack = 3
defense = 1

[resource]
script = ExtResource("1_mob")
mob_name = "Forest Wolf"
base_stats = SubResource("CombatStatsData_wolf")
gold_reward = 3
```

Keep `data/event/content/event_monster_content.tres` pointing to `res://data/event/mobs/wolf_mob.tres`.

For every matching card resource, replace exactly:

```text
path="res://scripts/card_data.gd"
```

with:

```text
path="res://scripts/card/card_data.gd"
```

Use this PowerShell command and inspect its reported file list before saving:

```powershell
$cards = Get-ChildItem data/cards -File -Filter *.tres | Where-Object { Select-String -Quiet -LiteralPath $_.FullName -SimpleMatch 'path="res://scripts/card_data.gd"' }
$cards | Select-Object -ExpandProperty FullName
$cards | ForEach-Object { (Get-Content -Raw -LiteralPath $_.FullName).Replace('path="res://scripts/card_data.gd"', 'path="res://scripts/card/card_data.gd"') | Set-Content -LiteralPath $_.FullName -Encoding utf8 }
```

- [ ] **Step 4: Run the resource and behavior checks**

Run:

```powershell
Godot --headless --path . --script res://tests/combat_model_test.gd
$staleCards = Get-ChildItem data/cards -File -Filter *.tres | Select-String -SimpleMatch 'res://scripts/card_data.gd'
if ($staleCards) { $staleCards; exit 1 }
$missing = Get-ChildItem -Recurse -File -Include *.gd,*.tscn,*.tres | ForEach-Object { $file = $_; $line = 0; Get-Content -LiteralPath $file.FullName | ForEach-Object { $line++; if ($_ -match 'path="(res://[^"]+)"' -and -not (Test-Path ($Matches[1] -replace '^res://',''))) { "$($file.FullName):$line $($Matches[1])" } } }
if ($missing) { $missing; exit 1 }
```

Expected: all commands exit with code `0` and print no stale or missing resource paths.

- [ ] **Step 5: Commit this unit of work**

Stage only the resource files changed by this task and `tests/combat_model_test.gd`, then commit:

```powershell
git commit -m "fix: repair combat content resource references"
```

## Task 5: Final project verification and handoff

**Files:**
- Modify only if a verification failure identifies a defect in a task file.
- Verify: `project.godot`, `scenes/game/game_manager.tscn`, all `.gd` / `.tres` / `.tscn` files under `scripts`, `data`, and `scenes`.

**Interfaces:**
- Consumes the completed shared combat API, player definition, monster definition, and card-resource repairs.
- Produces verified project loading behavior and a clean list of changes attributable to this refactor.

- [ ] **Step 1: Run all custom model tests**

Run:

```powershell
Godot --headless --path . --script res://tests/combat_model_test.gd
```

Expected: exit code `0`.

- [ ] **Step 2: Run a headless project load**

Run:

```powershell
Godot --headless --path . --editor --quit
```

Expected: exit code `0` with no parser errors, missing script errors, or missing resource errors.

- [ ] **Step 3: Inspect refactor-specific references**

Run:

```powershell
Get-ChildItem scripts,data,scenes -Recurse -File -Include *.gd,*.tres,*.tscn | Select-String -Pattern 'CharacterStats|CharacterStatsInstance|stats_template|res://scripts/card_data.gd'
```

Expected: no output. If output occurs, repair each listed reference before moving on.

- [ ] **Step 4: Review only intended changes**

Run:

```powershell
git diff -- scripts/combat scripts/player scripts/game/event/mob_data.gd scripts/game/event/mob_instance.gd scripts/game_manager.gd scenes/game/game_manager.tscn data/player data/event/mobs data/event/content data/cards tests
```

Expected: diff contains only the model migration, resource repairs, and regression test changes described above.

- [ ] **Step 5: Commit any final verification fixes**

If Steps 1–4 required corrections, stage only those corrected task files and commit:

```powershell
git commit -m "test: verify combat data model refactor"
```

If Steps 1–4 required no corrections, do not create an empty commit.
