# Task 2 Report — Composable Card Effect Rules

**Date:** 2026-07-31
**Baseline:** `65ac4dd475b68d7836f3912e11d38bc174f2dba4`
**Scope:** Task 2 only

## Implemented

- Added `CardResolutionContext` as an isolated, pre-card snapshot. It copies card-query data, full-chain position, resolution history, remaining-card list, and player/monster HP and defense values. Its query methods return copied card snapshots and expose no combat-state mutators.
- Added `CardResolutionDraft`, which starts from a card's base damage/defense/heal, clamps negative draft values to zero, and emits effects in the required order: `DAMAGE` → monster, `ADD_DEFENSE` → player, `HEAL` → player, then appended extras in operation order.
- Added the `CardCondition`, `CardOperation`, and `CardRule` resource contracts. Rules apply operations only when their optional condition passes; none of these types mutates encounter state directly.
- Added all eight configured conditions:
  - previous card has tag/type;
  - resolved-history tag;
  - resolved-card count comparison;
  - player and monster HP-ratio comparisons;
  - first/last card checks.
- Added all five operations: add/multiply damage, add defense, add heal, and append an extra `CombatEffect`.
- Added `CardData.effect_rules: Array[CardRule] = []` without removing or renaming existing serialized card fields. The focused test loads the existing `AllThingsRevival.tres` resource and verifies its existing values plus the default empty rule array.
- Expanded `tests/combat_service_test.gd` to cover snapshot isolation, all conditions, all operations, conditional/unconditional/blocked rules, deterministic effect ordering, zero clamping, and legacy `.tres` compatibility.

## TDD Evidence

- Added the Task 2 focused tests before implementation.
- Initial focused run failed as expected because the Task 2 context, draft, rule, condition, and operation scripts did not yet exist.
- After implementation, the focused test exits successfully.

## Verification

Commands run from `D:\project\MonoCard\mono-card-card-chain-combat`:

```text
D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe --headless --path . --script tests/combat_service_test.gd
gdformat <Task 2 GDScript files>
gdlint <Task 2 GDScript files>
git diff --check
```

Results:

- Focused Godot test: exit code 0.
- `gdformat`: clean after formatting.
- `gdlint`: `Success: no problems found` for all Task 2 GDScript files.
- `git diff --check`: no whitespace errors.

## Scope / Concerns

- Only Task 2 implementation files, their Godot `.uid` files, the focused test, and this report are intended for staging.
- Task 3 will extend the context with chain-rule and action-batch data; Task 2 intentionally does not include those types or exports.
