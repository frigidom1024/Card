# Task 4 Report — Monster next-action resolver

## Scope completed

- Added `MobInstance.next_action()` as the service-facing action-selection contract and retained `get_next_action()` as a compatibility wrapper.
- Added `MobInstance.duplicate_for_encounter()` to duplicate mutable runtime stats, preserve the shared immutable `MobData`, and reset `action_index`.
- Added `MobActionResolver.to_effects()` for attack, defend, and heal effects; unsupported demo action types return no effects.
- Added model and service coverage for action sequencing, encounter duplication, resolver mappings, source metadata, negative-value clamping, and unsupported types.

## Verification

| Command | Result |
| --- | --- |
| `D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe --headless --path . --script tests/combat_service_test.gd` | PASS (exit 0) |
| `D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe --headless --path . --script tests/combat_model_test.gd` | PASS (exit 0; existing validation warnings only) |
| `gdlint scripts/combat/mob_action_resolver.gd scripts/game/event/mob_instance.gd tests/combat_service_test.gd` | PASS |
| `gdformat --check scripts/combat/mob_action_resolver.gd scripts/game/event/mob_instance.gd tests/combat_service_test.gd` | PASS |
| `gdlint tests/combat_model_test.gd` | Known pre-existing failure: long-line and duplicated-load lint debt outside Task 4 (52 findings after formatting the Task 4 block) |
| `gdformat --check tests/combat_model_test.gd` | Known pre-existing formatting debt outside Task 4; no unrelated reformatting applied |

No `.uid` sidecar was required or generated for `mob_action_resolver.gd` by Godot 4.7.