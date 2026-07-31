# Task 5 Report — CombatService

## Scope
- Added `scripts/combat/combat_service.gd`.
- Added end-to-end `CombatService` coverage in `tests/combat_service_test.gd`.

## Implementation
- Resolves encounters using isolated player-stat and encounter-monster runtime copies while preserving card-chain order.
- Resolves root effects and root chain-rule registration without a monster response.
- Resolves ordinary card context, draft, ordered rules, effects, chain batches, and monster actions.
- Emits copied combat-step snapshots for roots, player cards, monster actions, including null-action empty steps.
- Stops immediately on victory or defeat; emits the tail-card removal penalty only for retreat.

## Verification
- `D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe --headless --path . --script tests/combat_service_test.gd`
  - Passed (exit code 0).
