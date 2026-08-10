# STACK//STRIKE Brand Name Verification

**Date:** 2026-08-10
**Reviewed range:** `cde484b..eec5e24`
**Implementation commit:** `eec5e24` (`feat: rename game to STACK//STRIKE`)

## Change Scope Reviewed

The committed branding range is limited to three files:

- `project.godot`: one player-facing configuration line changes `[application] config/name` to `STACK//STRIKE`.
- `scenes/home/main_menu_screen.tscn`: only the text values of the existing `Label` nodes `GameLogo` and `GameSubtitle` change, respectively, to `STACK//STRIKE` and `BUILD A DECK. BREAK THE BOARD.`
- `tests/home_screen_flow_test.gd`: precise regression assertions load `project.godot` and require the exact application name, title-label text, and subtitle-label text. The existing home-screen-flow assertions are otherwise retained.

No scene paths, node names, layout/theme values, project startup settings, or gameplay code are in this change range.

## Focused Home-Screen Flow Test

Both focused runs used the Godot console executable:

```powershell
& 'D:\project\singularity-factory\.Codex\tools\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --script res://tests/home_screen_flow_test.gd
```

Each isolated worktree was first opened with `--headless --editor --path . --quit` so Godot could register global script classes before the test script was executed.

### Baseline: `cde484b`

A temporary detached git worktree at `cde484b` was used and removed after the run.

- **Focused-test exit code:** `1`
- **Failed assertions:**
  1. `menu exposes version footer`
  2. `root option renders compact playstyle tags in a muted badge`

### Current implementation: `eec5e24`

A separate temporary detached git worktree at `eec5e24` was used and removed after the run.

- **Focused-test exit code:** `1`
- **Failed assertions:**
  1. `menu exposes version footer`
  2. `root option renders compact playstyle tags in a muted badge`

The failure list and non-zero focused-test exit code are unchanged from the baseline commit.

## Brand-Specific Smoke Check

The committed `eec5e24` sources contain all target values exactly:

| Source | Verified value |
| --- | --- |
| `project.godot` `[application] config/name` | `STACK//STRIKE` |
| `SafeArea/Layout/LogoBlock/GameLogo.text` | `STACK//STRIKE` |
| `SafeArea/Layout/LogoBlock/GameSubtitle.text` | `BUILD A DECK. BREAK THE BOARD.` |

The focused test also contains exact assertions for those three brand values.

## Editor Parse Smoke

Command:

```powershell
& 'D:\project\singularity-factory\.Codex\tools\Godot_v4.7.1-stable_win64_console.exe' --headless --editor --path . --quit
```

- **Exit code:** `0`
- **Result:** Godot completed the editor parse smoke without a parse error attributed to `project.godot` or `main_menu_screen.tscn`.
- **Existing non-task diagnostics:** the output is not claimed to be clean. It includes the `GitPlugin` construction diagnostic, invalid-UID fallback warnings for existing resources, and exit-time ObjectDB/resource-leak diagnostics. These warnings predate or are outside this branding-only scope and do not change the zero exit code.

## Conclusion

**The STACK//STRIKE brand rename passes verification.** The exact application name, main-menu logo, and subtitle are present in the implementation and covered by precise test assertions. The two focused-test failures are baseline failures already present at `cde484b`; they cannot be attributed to this branding change.
