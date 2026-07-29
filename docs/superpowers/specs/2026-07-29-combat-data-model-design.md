# Combat Data Model Refactor Design

**Date:** 2026-07-29  
**Status:** Proposed and approved in discussion; pending review of this written specification.

## Goal

Unify player, monster, boss, and summon combat attributes under a shared model without requiring a separate external stats resource file for every unit.

The design must ensure that configuration resources remain immutable during play and that every encounter owns independent mutable combat state.

## Non-goals

- Do not add a separate `*_stats.tres` file for each monster.
- Do not implement card effects, combat UI, map generation, or save/load in this refactor.
- Do not redesign card definitions beyond repairing broken resource references needed for project loading.

## Target Model

```text
Static definition resources (.tres)
  PlayerData / MobData / future BossData / future SummonData
      └─ base_stats: CombatStatsData (inline sub-resource)

Runtime state objects
  PlayerInstance / MobInstance
      └─ stats: CombatStats
```

### Static data: `CombatStatsData`

`CombatStatsData` is a `Resource` used only for base, inspector-editable values:

- `max_hp`
- `attack`
- `defense`

It is normally saved as an inline sub-resource inside its owning unit definition. It may be extracted as a reusable resource only when there is genuine deliberate reuse.

### Runtime data: `CombatStats`

`CombatStats` is a `RefCounted` value owned by one runtime unit. It contains mutable current values:

- `max_hp`
- `hp`
- `attack`
- `defense`

It exposes common combat operations:

- create from `CombatStatsData`
- `take_damage(amount)`
- `heal(amount)`
- `add_defense(amount)`
- `modify_attack(amount)`
- `is_alive()`

No gameplay code should mutate `hp`, `attack`, or `defense` through a static definition resource.

### Monster data and instances

`MobData` remains a static `Resource` and owns:

- name
- `base_stats`
- action definitions
- gold reward
- card reward pool

It must not hold per-encounter data such as current HP, action index, or temporary effects.

`MobInstance` is a `RefCounted` runtime object and owns:

- `data: MobData`
- `stats: CombatStats`
- `action_index`

Each generated enemy gets a fresh `MobInstance` using a copy of the definition's base stats.

### Player data

Add `PlayerData` as an optional static definition for the player's starting stats. It uses the same `base_stats: CombatStatsData` field as monsters. Since the project currently has one player, its stats will be held in a single `PlayerData` resource; it is not a per-character template system.

`PlayerInstance` is deferred until the gameplay flow needs player runtime stats. For this refactor, `GameManager` can create `CombatStats` directly from `PlayerData`.

## Resource layout

```text
data/
  cards/
    card_library.tres
    definitions/*.tres
  mobs/
    wolf_mob.tres
  players/
    player_data.tres
  events/
    content/*.tres
    event_library.tres
```

The existing `data/event/` directory will be renamed to `data/events/` only if all references can be updated together. Resource type scripts remain under `scripts/` and are not co-located with content files.

## Migration Plan

1. Replace `CharacterStats` with `CombatStatsData` (static base attributes).
2. Replace `CharacterStatsInstance` with `CombatStats` (runtime mutable state).
3. Add `MobInstance`; move `stats` and `_action_index` out of `MobData`.
4. Change `MobData` to expose `base_stats: CombatStatsData` rather than an incomplete mix of `max_hp` and `stats_template`.
5. Make the wolf resource valid, named, and referenced by monster event content.
6. Add a single `PlayerData` resource containing inline base stats, and initialize `GameManager` runtime stats from it.
7. Repair moved `CardData` script paths in card resources so `CardLibrary` can load consistently.
8. Keep the event-library wiring out of scope except for preserving valid data types and references.

## Compatibility and Safety Rules

- Existing card definitions continue to be immutable `CardData` resources; `CardInstance` remains their runtime counterpart.
- Existing unrelated user modifications are not reverted or staged.
- If a data resource is incomplete and unused, it is either repaired into a valid example or removed only after all references are verified absent.
- Each resource rename is validated by checking project-wide `res://` path references.

## Acceptance Criteria

- No `.tres` resource points to the removed `res://scripts/card_data.gd` path.
- Monster event content resolves to a real, valid monster definition resource.
- `MobData` contains no encounter-mutating fields or undefined references.
- One `MobData` resource can safely produce multiple independent `MobInstance` objects.
- Player and monster runtime stats use the same `CombatStats` API.
- Project script parsing and resource-reference checks finish without errors attributable to this refactor.
