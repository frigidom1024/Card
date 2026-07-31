# Task 3 Report — Root Chain Action Batches

**Date:** 2026-07-31
**Baseline:** `babd796c9c71f549ca05d0a2d4f3c2b1e8323a95`
**Scope:** Task 3 only

## Implemented

- Added the per-encounter `ChainRule` runtime value, including its rule ID, required card tag, configured and remaining match counts, source name, and open-batch state.
- Added the stateless `RootChainRuleProvider` contract and `WeaponComboRootRuleProvider`. The demo provider defaults to `WEAPON` and a two-card match, then creates a fresh `weapon_combo` runtime rule from the root-card context.
- Added `ChainRuleTracker` with the specified return-value contract:
  - the first matching weapon opens a batch and defers its monster action;
  - an adjacent second weapon closes that batch and requests exactly one action;
  - a nonmatching card closes an incomplete weapon batch before resolving, then closes its own ordinary batch afterward;
  - a final incomplete batch closes through `flush_pending()`;
  - without rules, ordinary cards return `false` from `begin_card()` and `true` from `finish_card()`;
  - duplicate rule IDs retain only the first runtime rule, preventing stacked identical demo combos.
- Extended `CombatState` with encounter-local `active_chain_rules`, `current_batch_id`, and `current_batch_card_count` fields.
- Extended `CardResolutionContext` to snapshot only active rule IDs plus the two batch scalars; it never exposes mutable `ChainRule` objects.
- Added `CardData.root_rule_providers: Array[RootChainRuleProvider] = []` while preserving legacy card fields.
- Added focused timing and snapshot tests covering `ROOT -> WEAPON -> WEAPON -> HEAL`, `ROOT -> WEAPON -> HEAL -> WEAPON`, `ROOT -> WEAPON` flush behavior, no-rule behavior, duplicate demo-rule selection, and copy safety.
- Added the four Godot-generated `.uid` companions for the new scripts.

## TDD Evidence

- Added Task 3 timing tests before the runtime classes existed.
- Initial focused run failed as expected with missing preloads for `chain_rule.gd`, `chain_rule_tracker.gd`, and `weapon_combo_root_rule_provider.gd` (exit code 1).
- After implementation, an initial parse failure identified that the new `class_name` scripts had no Godot `.uid` files and therefore were not registered in the project class cache. A headless editor scan generated their `.uid` companions; the subsequent focused test passed.

## Verification

Commands run from `D:\project\MonoCard\mono-card-card-chain-combat`:

```text
D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe --headless --path . --script tests/combat_service_test.gd
gdformat --check <Task 3 GDScript files>
gdlint <Task 3 GDScript files>
git diff --check
```

Results:

- Focused Godot test: exit code 0.
- `gdformat --check`: all 8 Task 3 GDScript files unchanged.
- `gdlint`: `Success: no problems found` for all 8 Task 3 GDScript files.
- `git diff --check`: no whitespace errors.

## Scope / Concerns

- The staged change is limited to Task 3 runtime/provider/tracker files, their required `.uid` companions, the three requested existing domain files, the focused combat-service test, and this report.
- `CombatService` integration is intentionally deferred to Task 5. That task must call `begin_card()` and `finish_card()` only for non-root cards, so a root registers rules without directly triggering a monster action.