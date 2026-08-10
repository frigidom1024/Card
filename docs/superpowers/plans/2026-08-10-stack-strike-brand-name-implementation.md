# STACK//STRIKE Brand Name Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the active application and main-menu title copy with the confirmed brand name `STACK//STRIKE` and its tagline without changing menu flow or game identifiers.

**Architecture:** This is a data-only branding change. `project.godot` owns the operating-system/window application name, while `scenes/home/main_menu_screen.tscn` owns the player-facing main-menu labels. The existing scene-tree test will become the regression boundary for both the exact copy and the project configuration value.

**Tech Stack:** Godot 4.7, GDScript SceneTree tests, `.tscn` scene resources, `project.godot` configuration.

## Global Constraints

- Official display name is exactly `STACK//STRIKE`.
- Header tagline is exactly `BUILD A DECK. BREAK THE BOARD.`.
- The double slash is part of the display name and must not be converted to a single slash.
- Do not rename scene paths, script class names, save keys, resource identifiers, or the repository folder `mono-card`.
- Do not modify `run/main_scene`, autoload registration, or resource paths in `project.godot`.
- Do not change main-menu layout, palette, animation, mechanics, cards, combat, event behavior, or the existing `BEGIN PILGRIMAGE` button in this task.

---

## File Structure

| File | Responsibility |
|---|---|
| `project.godot` | Defines Godot's player-facing application/window name through `[application] config/name`. |
| `scenes/home/main_menu_screen.tscn` | Defines the existing `GameLogo` and `GameSubtitle` Label text shown on the active main menu. |
| `tests/home_screen_flow_test.gd` | Loads the project configuration and main-menu scene, then verifies exact brand copy while retaining flow checks. |

### Task 1: Add the branding regression expectations

**Files:**
- Modify: `tests/home_screen_flow_test.gd:3-5, 35-65`

**Interfaces:**
- Consumes: `res://project.godot`, `res://scenes/home/main_menu_screen.tscn`, and the existing `SceneTree` `_expect(condition: bool, message: String)` helper.
- Produces: A failing test when the app name, `GameLogo`, or `GameSubtitle` does not use the approved `STACK//STRIKE` branding.

- [ ] **Step 1: Add a project configuration path constant**

Directly below `MAIN_MENU_SCENE_PATH`, add the immutable location used by the test:

```gdscript
const PROJECT_CONFIG_PATH := "res://project.godot"
const MAIN_MENU_SCENE_PATH := "res://scenes/home/main_menu_screen.tscn"
```

- [ ] **Step 2: Replace the old menu-title assertions and add application-name assertions**

At the beginning of `_test_main_menu_structure_and_single_start_request()`, before loading the packed scene, insert:

```gdscript
var project_config := ConfigFile.new()
var config_error := project_config.load(PROJECT_CONFIG_PATH)
_expect(config_error == OK, "project configuration loads")
_expect(
	project_config.get_value("application", "config/name", "") == "STACK//STRIKE",
	"application config exposes the STACK//STRIKE display name"
)
```

Replace the two old copy expectations with:

```gdscript
_expect(logo != null and logo.text == "STACK//STRIKE", "menu exposes the STACK//STRIKE title")
_expect(
	subtitle != null and subtitle.text == "BUILD A DECK. BREAK THE BOARD.",
	"menu exposes the approved arcade deck-building tagline"
)
```

Do not change node paths, color assertions, layout assertions, signal assertions, or the test for the `BEGIN PILGRIMAGE` action.

- [ ] **Step 3: Run the focused test to verify the expectations fail on the old data**

Run:

```powershell
& godot --headless --path . -s res://tests/home_screen_flow_test.gd
```

Expected: a non-zero exit because `config/name`, `GameLogo.text`, and `GameSubtitle.text` still contain pre-rebrand strings.

- [ ] **Step 4: Commit the failing-test checkpoint**

```powershell
git add tests/home_screen_flow_test.gd
git commit -m "test: define STACK//STRIKE branding expectations"
```

### Task 2: Apply the approved display name and header copy

**Files:**
- Modify: `project.godot:10-14`
- Modify: `scenes/home/main_menu_screen.tscn:151-171`
- Test: `tests/home_screen_flow_test.gd`

**Interfaces:**
- Consumes: Task 1's exact string expectations.
- Produces: `config/name="STACK//STRIKE"`, `GameLogo.text="STACK//STRIKE"`, and `GameSubtitle.text="BUILD A DECK. BREAK THE BOARD."`.

- [ ] **Step 1: Set the Godot application name**

In `[application]` in `project.godot`, replace only this setting:

```ini
config/name="MonoCard"
```

with:

```ini
config/name="STACK//STRIKE"
```

Leave the following `run/main_scene`, `config/features`, and `config/icon` settings byte-for-byte unchanged.

- [ ] **Step 2: Set the existing menu labels**

In `scenes/home/main_menu_screen.tscn`, replace only the `text` property under these existing nodes:

```text
SafeArea/Layout/LogoBlock/GameLogo
SafeArea/Layout/LogoBlock/GameSubtitle
```

with:

```ini
text = "STACK//STRIKE"
text = "BUILD A DECK. BREAK THE BOARD."
```

Do not alter node names, `unique_id` values, fonts, colors, outlines, offsets, anchors, or button text.

- [ ] **Step 3: Run the focused home-screen regression test**

Run:

```powershell
& godot --headless --path . -s res://tests/home_screen_flow_test.gd
```

Expected: exit code `0`; the test reports no failed application-name or menu-copy expectations.

- [ ] **Step 4: Run a project parse smoke test**

Run:

```powershell
& godot --headless --path . --editor --quit
```

Expected: exit code `0` and no parse error for `project.godot` or `main_menu_screen.tscn`.

- [ ] **Step 5: Review the scoped diff**

Run:

```powershell
git diff -- project.godot scenes/home/main_menu_screen.tscn tests/home_screen_flow_test.gd
```

Expected: the diff is limited to one config string, two menu strings, and their focused regression expectations.

- [ ] **Step 6: Commit the implementation**

```powershell
git add project.godot scenes/home/main_menu_screen.tscn tests/home_screen_flow_test.gd
git commit -m "feat: rename game to STACK//STRIKE"
```

## Plan Self-Review

- **Spec coverage:** Task 2 sets the exact Godot display name and active main-menu header required by the approved specification. Task 1 verifies both sources and preserves the existing flow test. The excluded layout, mechanics, identifiers, paths, and CTA remain untouched.
- **Placeholder scan:** The plan contains no unresolved placeholders, deferred implementation wording, or unspecified test behavior.
- **Type consistency:** The test uses Godot's `ConfigFile`, `Error` constant `OK`, the existing `Label` variables, and the existing `_expect(bool, String)` signature. No new runtime API is introduced.

