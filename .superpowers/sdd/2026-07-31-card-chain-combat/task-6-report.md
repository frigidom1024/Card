# Task 6 Report — Combat Card Resource Fixtures

## Scope
- Added `tests/fixtures/cards/weapon_combo_root.tres`.
- Extended `tests/combat_service_test.gd` resource-load coverage.

## Coverage
- Loads every `*.tres` directly under `res://data/cards` as `CardData`.
- Verifies `AllThingsRevival.tres` retains an empty `effect_rules` array and that
  `CardResolutionDraft.from_card()` preserves its serialized base `heal` value.
- Loads an isolated root-card fixture with a typed inline
  `WeaponComboRootRuleProvider`, verifies it has exactly one provider, and
  verifies the provider class.

## Test-first evidence
- Before the fixture was created, the new regression test failed as expected
  because `res://tests/fixtures/cards/weapon_combo_root.tres` did not exist.
- After adding the fixture:
  - `D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe --headless --path . --script tests/combat_service_test.gd` — passed (exit 0).
  - `D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe --headless --path . --script tests/combat_model_test.gd` — passed (exit 0). Its existing invalid-event warnings were emitted as expected by that test suite.

## Formatting and lint
- `gdformat --check tests/combat_service_test.gd` reports that the pre-existing
  full test file would be reformatted.
- `gdlint tests/combat_service_test.gd` reports the same 12 pre-existing
  violations from baseline `2b5966e`: 11 long lines in the existing test body
  and the file-size rule (`max-file-lines`, baseline already has 1,028 lines).
  Task 6 adds none of the reported long-line violations. No unrelated
  whole-file formatting or lint cleanup was included.

## Commit scope
Only these Task 6 files are staged:
- `tests/fixtures/cards/weapon_combo_root.tres`
- `tests/combat_service_test.gd`
- `.superpowers/sdd/2026-07-31-card-chain-combat/task-6-report.md`