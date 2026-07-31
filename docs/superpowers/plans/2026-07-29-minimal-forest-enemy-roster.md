# Minimal Forest Enemy Roster Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic roster of three basic enemy definitions and one boss definition, with resource-backed event definitions ready for the existing event library.

**Architecture:** Keep combat behavior data-only: every `MobData` resource embeds `CombatStatsData` and has one inline `MobAction.Type.ATTACK`. Each enemy receives one `EventMonsterContent` and one `EventData`; `event_lib.tres` is populated with four fixed-count `EventEntry` records. The existing combat resolver is not expanded: this work defines the boss card reward in `MobData.card_rewards` for the resolver to grant when it is connected.

**Tech Stack:** Godot 4.7 resources (`.tres`), GDScript, headless Godot regression test.

## Global Constraints

- Keep every monster to exactly one `MobAction.Type.ATTACK` action; do not add defense, healing, buffs, debuffs, special actions, or action cycles.
- Keep `CombatStatsData` as an inline sub-resource inside each `MobData` file; do not create `*_stats.tres` files.
- Keep the card price ladder at 2, 4, 8, and 16 gold. Use fixed roster rewards only: 1, 2, 4, and 16 gold. No randomized reward pools, probability fields, or random reward selection.
- Basic enemies have no card rewards. The boss has exactly one `WorldTreeBranchCleaver` reward.
- Use event counts of exactly one (`min_count = 1`, `max_count = 1`) so all four event definitions generate deterministically.
- Do not change combat UI, combat turn scheduling, shop UI, map generation, or unrelated event migration files. The project must start without script or resource parse errors.

---

## File Structure

| Path | Change | Responsibility |
|---|---|---|
| `tests/combat_model_test.gd` | Modify | Validate all four `MobData` resources and the populated deterministic event library. |
| `data/event/mobs/rotwood_gnawer_mob.tres` | Create | 8 HP introductory enemy with one Attack 2 action and 1 gold reward. |
| `data/event/mobs/wolf_mob.tres` | Modify | Existing standard enemy; add one Attack 3 action and change gold reward from 3 to 2. |
| `data/event/mobs/miasma_shadow_lizard_mob.tres` | Create | 16 HP strong basic enemy with one Attack 4 action and 4 gold reward. |
| `data/event/mobs/miasma_grove_guardian_boss.tres` | Create | 30 HP boss with one Attack 5 action, 16 gold, and one `WorldTreeBranchCleaver` reward. |
| `data/event/content/rotwood_gnawer_monster_content.tres` | Create | Connect the gnawer mob to one monster encounter. |
| `data/event/content/forest_wolf_monster_content.tres` | Create | Connect the wolf mob to one monster encounter. |
| `data/event/content/miasma_shadow_lizard_monster_content.tres` | Create | Connect the lizard mob to one monster encounter. |
| `data/event/content/miasma_grove_guardian_boss_content.tres` | Create | Connect the boss mob to one boss encounter. |
| `data/event/events/rotwood_gnawer_event.tres` | Create | `MONSTER` event definition for the gnawer. |
| `data/event/events/forest_wolf_event.tres` | Create | `MONSTER` event definition for the wolf. |
| `data/event/events/miasma_shadow_lizard_event.tres` | Create | `MONSTER` event definition for the lizard. |
| `data/event/events/miasma_grove_guardian_boss_event.tres` | Create | `BOSS` event definition for the guardian. |
| `data/event/event_lib.tres` | Modify | Register all four event definitions with a deterministic count of one. |

## Task 1: Add and Validate the Enemy Definitions

**Files:**
- Create: `data/event/mobs/rotwood_gnawer_mob.tres`
- Modify: `data/event/mobs/wolf_mob.tres`
- Create: `data/event/mobs/miasma_shadow_lizard_mob.tres`
- Create: `data/event/mobs/miasma_grove_guardian_boss.tres`
- Modify: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes: `MobData.create_instance() -> MobInstance`, `MobAction.Type.ATTACK`, `CombatStatsData`, and `CardData` resource `res://data/cards/WorldTreeBranchCleaver.tres`.
- Produces: Four loadable `MobData` definitions that later event resources can reference.

- [ ] **Step 1: Add a failing roster-validation block to `tests/combat_model_test.gd`**

  Add these preloads after the existing `PlayerDataScript` preload:

  ```gdscript
  const MobActionScript = preload("res://scripts/game/event/mob_action.gd")
  const CardDataScript = preload("res://scripts/card/card_data.gd")
  ```

  Add this helper before `_expect`:

  ```gdscript
  func _expect_mob(
      resource_path: String,
      expected_name: String,
      expected_hp: int,
      expected_attack: int,
      expected_defense: int,
      expected_gold: int,
      expected_reward_count: int
  ) -> void:
      var mob = load(resource_path) as MobData
      _expect(mob != null, "%s loads" % resource_path)
      if mob == null:
          return
      _expect(mob.mob_name == expected_name, "%s keeps its display name" % resource_path)
      _expect(mob.base_stats != null, "%s has inline base stats" % resource_path)
      if mob.base_stats:
          _expect(mob.base_stats.max_hp == expected_hp, "%s has expected HP" % resource_path)
          _expect(mob.base_stats.attack == expected_attack, "%s has expected attack" % resource_path)
          _expect(mob.base_stats.defense == expected_defense, "%s has expected defense" % resource_path)
      _expect(mob.gold_reward == expected_gold, "%s has expected gold reward" % resource_path)
      _expect(mob.actions.size() == 1, "%s has one action" % resource_path)
      if mob.actions.size() == 1:
          _expect(mob.actions[0].type == MobActionScript.Type.ATTACK, "%s action is attack" % resource_path)
          _expect(mob.actions[0].value == expected_attack, "%s action value matches attack" % resource_path)
      _expect(mob.card_rewards.size() == expected_reward_count, "%s has expected fixed reward count" % resource_path)
      _expect(mob.create_instance().is_alive(), "%s creates a live encounter" % resource_path)
  ```

  In `_init`, after the existing wolf-resource assertions, add:

  ```gdscript
  _expect_mob("res://data/event/mobs/rotwood_gnawer_mob.tres", "Rotwood Gnawer", 8, 2, 0, 1, 0)
  _expect_mob("res://data/event/mobs/wolf_mob.tres", "Forest Wolf", 12, 3, 1, 2, 0)
  _expect_mob("res://data/event/mobs/miasma_shadow_lizard_mob.tres", "Miasma Shadow Lizard", 16, 4, 1, 4, 0)
  _expect_mob("res://data/event/mobs/miasma_grove_guardian_boss.tres", "Miasma Grove Guardian", 30, 5, 2, 16, 1)
  var guardian = load("res://data/event/mobs/miasma_grove_guardian_boss.tres") as MobData
  if guardian and guardian.card_rewards.size() == 1:
      var boss_card = guardian.card_rewards[0] as CardDataScript
      _expect(boss_card != null and boss_card.card_name == "World Tree Branch Cleaver", "boss reward is WorldTreeBranchCleaver")
  ```

- [ ] **Step 2: Run the regression test and verify the test fails because the three new mob resources do not exist and the wolf does not yet have an action or 2-gold reward**

  Run in PowerShell:

  ```powershell
  $godotHome = (Resolve-Path '.tmp\godot_user').Path
  $env:APPDATA = $godotHome
  $env:LOCALAPPDATA = $godotHome
  $env:USERPROFILE = $godotHome
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path $PWD --script res://tests/combat_model_test.gd
  ```

  Expected: non-zero exit or test errors referring to the missing `rotwood_gnawer_mob.tres`, `miasma_shadow_lizard_mob.tres`, and `miasma_grove_guardian_boss.tres` resources, plus the wolf action/reward assertions.

- [ ] **Step 3: Create the four exact mob definitions**

  Use `MobData`, `CombatStatsData`, and `MobAction` as the only scripts in every mob file. Keep each action as an inline `MobAction` sub-resource with `type = 0` (`ATTACK`), `value` equal to the unit attack, and a matching display description.

  | File | `mob_name` | `max_hp` | `attack` | `defense` | Action description | `gold_reward` | `card_rewards` |
  |---|---|---:|---:|---:|---|---:|---|
  | `data/event/mobs/rotwood_gnawer_mob.tres` | `Rotwood Gnawer` | 8 | 2 | 0 | `Gnaw` | 1 | Empty |
  | `data/event/mobs/wolf_mob.tres` | `Forest Wolf` | 12 | 3 | 1 | `Bite` | 2 | Empty |
  | `data/event/mobs/miasma_shadow_lizard_mob.tres` | `Miasma Shadow Lizard` | 16 | 4 | 1 | `Miasma Bite` | 4 | Empty |
  | `data/event/mobs/miasma_grove_guardian_boss.tres` | `Miasma Grove Guardian` | 30 | 5 | 2 | `Root Lash` | 16 | `[res://data/cards/WorldTreeBranchCleaver.tres]` |

  The boss resource must contain an external `CardData` resource reference and set `card_rewards` as a typed `Array[ExtResource("<card-reference-id>")]` containing exactly that card. The other three resources must omit `card_rewards`, preserving `MobData`'s empty default array.

- [ ] **Step 4: Run the regression test and verify all roster assertions pass**

  Run the same headless Godot command from Step 2.

  Expected: exit code `0`, no assertion errors, and each of the four resource paths loads successfully.

- [ ] **Step 5: Commit the mob-definition task only**

  ```powershell
  git add -- tests/combat_model_test.gd data/event/mobs/rotwood_gnawer_mob.tres data/event/mobs/wolf_mob.tres data/event/mobs/miasma_shadow_lizard_mob.tres data/event/mobs/miasma_grove_guardian_boss.tres
  git diff --cached --check
  git commit -m "feat: add minimal forest enemy roster"
  ```

## Task 2: Register One Deterministic Event for Each Enemy

**Files:**
- Create: `data/event/content/rotwood_gnawer_monster_content.tres`
- Create: `data/event/content/forest_wolf_monster_content.tres`
- Create: `data/event/content/miasma_shadow_lizard_monster_content.tres`
- Create: `data/event/content/miasma_grove_guardian_boss_content.tres`
- Create: `data/event/events/rotwood_gnawer_event.tres`
- Create: `data/event/events/forest_wolf_event.tres`
- Create: `data/event/events/miasma_shadow_lizard_event.tres`
- Create: `data/event/events/miasma_grove_guardian_boss_event.tres`
- Modify: `data/event/event_lib.tres`
- Modify: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes: `EventMonsterContent.mob: MobData`, `EventMonsterContent.count: int`, `EventData.event_type`, and `EventLib.generate_event_datas() -> Array[EventData]`.
- Produces: A library that always produces exactly the three `MONSTER` definitions and one `BOSS` definition once each.

- [ ] **Step 1: Add a failing deterministic-library test to `tests/combat_model_test.gd`**

  Add this code in `_init` after the roster assertions:

  ```gdscript
  var event_lib = load("res://data/event/event_lib.tres") as EventLib
  _expect(event_lib != null, "enemy event library loads")
  if event_lib:
      var generated_events = event_lib.generate_event_datas()
      _expect(generated_events.size() == 4, "enemy event library generates four fixed events")
      var expected_event_types := {
          "rotwood_gnawer": EventData.EventType.MONSTER,
          "forest_wolf": EventData.EventType.MONSTER,
          "miasma_shadow_lizard": EventData.EventType.MONSTER,
          "miasma_grove_guardian": EventData.EventType.BOSS,
      }
      for event in generated_events:
          _expect(event.event_id in expected_event_types, "generated event has a roster ID")
          if event.event_id in expected_event_types:
              _expect(event.event_type == expected_event_types[event.event_id], "%s has correct event type" % event.event_id)
          var monster_content = event.content as EventMonsterContent
          _expect(monster_content != null, "%s has monster content" % event.event_id)
          if monster_content:
              _expect(monster_content.count == 1, "%s spawns one mob" % event.event_id)
              _expect(monster_content.mob != null, "%s resolves its mob" % event.event_id)
  ```

- [ ] **Step 2: Run the regression test and verify the library assertions fail because `event_lib.tres` has no entries**

  Run the same headless Godot command from Task 1, Step 2.

  Expected: exit code `1` with `enemy event library generates four fixed events` failing.

- [ ] **Step 3: Create the four content resources and four event definitions**

  Each content resource must use `EventMonsterContent`, reference the matching `MobData` file, and set `count = 1`.

  | Content file | Mob reference |
  |---|---|
  | `data/event/content/rotwood_gnawer_monster_content.tres` | `res://data/event/mobs/rotwood_gnawer_mob.tres` |
  | `data/event/content/forest_wolf_monster_content.tres` | `res://data/event/mobs/wolf_mob.tres` |
  | `data/event/content/miasma_shadow_lizard_monster_content.tres` | `res://data/event/mobs/miasma_shadow_lizard_mob.tres` |
  | `data/event/content/miasma_grove_guardian_boss_content.tres` | `res://data/event/mobs/miasma_grove_guardian_boss.tres` |

  Each event definition must use `EventData`, reference the matching content resource, leave `size` at its `Vector2i.ONE` default, and use these exact identity fields:

  | Event file | `event_id` | `event_type` |
  |---|---|---:|
  | `data/event/events/rotwood_gnawer_event.tres` | `rotwood_gnawer` | `2` (`MONSTER`) |
  | `data/event/events/forest_wolf_event.tres` | `forest_wolf` | `2` (`MONSTER`) |
  | `data/event/events/miasma_shadow_lizard_event.tres` | `miasma_shadow_lizard` | `2` (`MONSTER`) |
  | `data/event/events/miasma_grove_guardian_boss_event.tres` | `miasma_grove_guardian` | `3` (`BOSS`) |

- [ ] **Step 4: Populate `data/event/event_lib.tres` with four fixed entries**

  Add external references to `event_lib.gd`, `event_entry.gd`, and all four event resources. Create four inline `EventEntry` sub-resources. Each one must set:

  ```text
  script = ExtResource("event_entry_script")
  event_data = ExtResource("matching_event")
  min_count = 1
  max_count = 1
  ```

  Set the root `entries` property to an `Array[ExtResource("event_entry_script")]` that lists all four sub-resources in this order:

  ```text
  rotwood_gnawer, forest_wolf, miasma_shadow_lizard, miasma_grove_guardian
  ```

- [ ] **Step 5: Run the regression test and verify all event-library assertions pass**

  Run the same headless Godot command from Task 1, Step 2.

  Expected: exit code `0`; `generate_event_datas()` returns four entries because every library entry has a fixed count of one.

- [ ] **Step 6: Commit the event-registration task only**

  ```powershell
  git add -- tests/combat_model_test.gd data/event/content/rotwood_gnawer_monster_content.tres data/event/content/forest_wolf_monster_content.tres data/event/content/miasma_shadow_lizard_monster_content.tres data/event/content/miasma_grove_guardian_boss_content.tres data/event/events/rotwood_gnawer_event.tres data/event/events/forest_wolf_event.tres data/event/events/miasma_shadow_lizard_event.tres data/event/events/miasma_grove_guardian_boss_event.tres data/event/event_lib.tres
  git diff --cached --check
  git commit -m "feat: register forest enemy events"
  ```

## Task 3: Perform End-to-End Data Validation

**Files:**
- Modify: none unless a validation failure identifies an incorrect resource path or field value.
- Test: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes: The completed roster resources and `event_lib.tres` from Tasks 1 and 2.
- Produces: Fresh evidence that resources, global classes, and the main scene load without errors.

- [ ] **Step 1: Run the full combat and roster regression test in a fresh Godot user directory**

  ```powershell
  $godotHome = (Resolve-Path '.tmp\godot_user').Path
  $env:APPDATA = $godotHome
  $env:LOCALAPPDATA = $godotHome
  $env:USERPROFILE = $godotHome
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path $PWD --script res://tests/combat_model_test.gd
  ```

  Expected: exit code `0`.

- [ ] **Step 2: Start the configured main scene for 30 frames and reject parser or script-load errors**

  ```powershell
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path $PWD --quit-after 30
  ```

  Expected: exit code `0` and no `Parse Error:`, `SCRIPT ERROR:`, or `Failed to load script` output.

- [ ] **Step 3: Validate static project resource paths and diff formatting**

  ```powershell
  git diff --check
  ```

  Expected: exit code `0`.

- [ ] **Step 4: Inspect the staged or committed diff to verify it contains only the roster, event, and test files named in this plan**

  ```powershell
  git status --short
  git show --stat --oneline -1
  ```

  Expected: no unrelated user migration or editor-configuration files were included in either roster commit.