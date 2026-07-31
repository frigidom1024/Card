# Task 1 Fix Round 1 Report

**Baseline:** `1478d70` (`feat: add combat runtime primitives`)

## Reviewer Findings Addressed

1. Added `CombatEffect.duplicate_runtime()`.
2. Updated `CombatStep` to deep-copy each `CombatEffect` and added `CombatStep.duplicate_runtime()`, which preserves `kind`, `source_name`, effects, and all four `CombatStats` snapshots.
3. Added `CombatPenalty.duplicate_runtime()`.
4. Updated `CombatResult` to deep-copy every `CombatStep` and `CombatPenalty`, so result snapshots do not retain caller-owned objects.
5. Extended `tests/combat_service_test.gd` with mutation-isolation coverage for effects, steps, penalties, and their copied snapshots.

## Root Cause

`Array.duplicate()` duplicates only the array container. The previous constructors therefore retained aliases to mutable `CombatEffect`, `CombatStep`, and `CombatPenalty` instances supplied by callers.

## Test-First Evidence

Before production changes, the added Godot test exited with status `1` and reported the expected missing duplication methods plus failed deep-copy assertions for step effects, result steps, and result penalties.

## Verification

All commands were run from `D:\project\MonoCard\mono-card-card-chain-combat`:

```text
D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe --headless --path . --script tests/combat_service_test.gd
# exit 0

gdformat --check scripts/combat/combat_effect.gd scripts/combat/combat_step.gd scripts/combat/combat_penalty.gd scripts/combat/combat_result.gd tests/combat_service_test.gd
# exit 0; 5 files would be left unchanged

gdlint scripts/combat/combat_effect.gd scripts/combat/combat_step.gd scripts/combat/combat_penalty.gd scripts/combat/combat_result.gd tests/combat_service_test.gd
# exit 0; Success: no problems found
```

## Scope

Changed only the four Task 1 combat runtime model files, the existing combat service test, and this required repair report.

## Concerns

None identified. The test covers mutable caller-owned inputs used by the current runtime model; future mutable fields added to these value objects should also be copied by their respective `duplicate_runtime()` implementations.