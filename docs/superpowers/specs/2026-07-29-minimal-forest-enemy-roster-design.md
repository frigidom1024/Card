# Minimal Forest Enemy Roster Design

**Date:** 2026-07-29
**Status:** Approved in discussion; awaiting review of this written specification.

## Goal

Add the smallest practical enemy roster needed to run the core gameplay loop:

```text
encounter -> basic combat -> gold reward -> shop purchase -> boss reward
```

The first playable version must remain deterministic and data-driven. It should not require random drops, multi-turn skill logic, buffs, healing, debuffs, or additional combat systems.

## Scope

- Add three basic enemy definitions and one boss definition using the existing `MobData` resource type.
- Keep `CombatStatsData` inline in every enemy resource.
- Give every enemy exactly one `MobAction.Type.ATTACK` action.
- Use fixed gold rewards aligned to card prices of 2, 4, 8, and 16 gold.
- Give the boss one fixed card reward.

## Non-goals

- No randomized reward pools or drop-rate fields.
- No elite enemy tier.
- No `DEFEND`, `HEAL`, `BUFF`, `DEBUFF`, or `SPECIAL` monster actions.
- No new card definitions.
- No redesign of combat UI, shop UI, map generation, or turn scheduling.

## Roster

| ID | Enemy | Role | HP | Attack | Defense | Action | Gold | Fixed card reward |
|---|---|---|---:|---:|---:|---|---:|---|
| `rotwood_gnawer` | 腐木啃噬鼠 | Introductory enemy | 8 | 2 | 0 | Attack 2 | 1 | None |
| `forest_wolf` | 森林狼 | Standard enemy | 12 | 3 | 1 | Attack 3 | 2 | None |
| `miasma_shadow_lizard` | 瘴气影蜥 | Strong basic enemy | 16 | 4 | 1 | Attack 4 | 4 | None |
| `miasma_grove_guardian` | 瘴林古树守卫 | Area boss | 30 | 5 | 2 | Attack 5 | 16 | `WorldTreeBranchCleaver` |

## Balance Rationale

- The introductory mouse can be defeated quickly and pays half the cost of a 2-gold card.
- The wolf matches the current combat baseline while paying for one 2-gold card.
- The lizard represents the final basic-enemy step and pays for one 4-gold card.
- The boss represents the area endpoint. Its 16-gold reward buys one top-tier card and its fixed `WorldTreeBranchCleaver` reward provides a reliable combat payoff.
- The boss reward is intentionally generous because it is issued once per area. Basic enemies only grant gold, preserving the value of shop choices.

## Data Representation

Each resource uses this existing data model:

```text
MobData
  mob_name
  base_stats: CombatStatsData (inline)
  actions: [MobAction(ATTACK, value)]
  gold_reward
  card_rewards
```

The boss `card_rewards` array contains exactly one reference: `WorldTreeBranchCleaver`. All other enemies have an empty `card_rewards` array.

For this first version, `card_rewards` has explicit fixed-reward semantics: after defeating the enemy, grant every card in the array once. As only the boss has one item, no random-selection logic is required.

## Resource Layout

```text
data/event/mobs/
  rotwood_gnawer_mob.tres
  wolf_mob.tres
  miasma_shadow_lizard_mob.tres
  miasma_grove_guardian_boss.tres
```

`wolf_mob.tres` is the existing monster definition and will be updated to include its single attack action and 2-gold reward. The other three resources are new.

## Event Integration

Each enemy must be available through a separate monster event definition. The event layer should retain its current rule of one `MobData` reference plus a count. The initial path should use a count of one for all four definitions so combat behavior stays simple and each reward is unambiguous.

## Acceptance Criteria

- All four resources load as `MobData` and create live `MobInstance` objects.
- Each resource has inline `CombatStatsData` and exactly one attack action.
- Monster attributes and gold rewards match the roster table.
- Basic enemies have no card rewards.
- The boss has a single fixed `WorldTreeBranchCleaver` card reward.
- All resource paths resolve and the project starts without script or resource parse errors.