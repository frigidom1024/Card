# Homepage Visual Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved centered home-menu layout with a translucent ActionPanel and dark-blue, gilt interactive button states without changing the menu routing flow.

**Architecture:** Keep the page as a self-contained `Control` scene. The scene owns readability overlays, the title layout, ActionPanel and button styles; `MainMenuScreen` only updates its existing node path while retaining single-fire signal behavior. The existing scene test remains the regression boundary for layout, visuals and routing.

**Tech Stack:** Godot 4.7, GDScript, `.tscn` scenes, Godot `StyleBoxFlat`, `GradientTexture2D`, existing headless scene test runner.

## Global Constraints

- Preserve the existing `开始游戏 → 牌根选择 → 开始探索` route and `start_game_requested` signal.
- Keep current user-authored title-font changes in the worktree; do not reset or overwrite unrelated changes.
- Do not add image assets, scripts, menu actions, animations, sounds or external dependencies.
- Use one `PanelContainer` named `ActionPanel`; its visual weight remains lower than its child CTA.
- Use the finalized Chinese CTA copy: `踏上巡礼`.
- Do not create git commits unless the user explicitly requests one.

---

### Task 1: Add the Centered ActionPanel Structure

**Files:**
- Modify: `tests/home_screen_flow_test.gd:24-70`
- Modify: `scenes/home/main_menu_screen.tscn:58-163`
- Modify: `scripts/home/main_menu_screen.gd:6`

**Interfaces:**
- Consumes: `MainMenuScreen.start_game_requested` and the existing start-button single-fire guard.
- Produces: `SafeArea/Layout/ActionBlock/ActionPanel/MenuList/StartGameButton` as the stable start-button path for scene script and test.

- [ ] **Step 1: Write the failing menu-structure assertions**

In `_test_main_menu_structure_and_single_start_request()`, replace the direct start button lookup with:

```gdscript
var action_panel := menu.get_node_or_null(
    "SafeArea/Layout/ActionBlock/ActionPanel"
) as PanelContainer
var menu_list := menu.get_node_or_null(
    "SafeArea/Layout/ActionBlock/ActionPanel/MenuList"
) as VBoxContainer
var start := menu.get_node_or_null(
    "SafeArea/Layout/ActionBlock/ActionPanel/MenuList/StartGameButton"
) as Button

_expect(action_panel != null, "menu exposes a translucent action panel")
_expect(
    action_panel != null and action_panel.custom_minimum_size == Vector2(430, 150),
    "action panel reserves the approved centered menu area"
)
_expect(menu_list != null, "action panel owns an expandable vertical menu list")
_expect(start != null and start.text == "踏上巡礼", "menu exposes the pilgrimage CTA")
```

Remove the old direct `StartGameButton` lookup and its `开始游戏` assertion. Keep the signal test and emit `pressed` from this new `start` variable.

- [ ] **Step 2: Run the focused home-menu test and confirm failure**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\home_screen_flow_test.gd
```

Expected: FAIL because `ActionPanel`, `MenuList`, and the nested button path do not exist.

- [ ] **Step 3: Add the ActionPanel hierarchy and retain signal behavior**

In `scenes/home/main_menu_screen.tscn`, change the action subtree to:

```text
ActionBlock (CenterContainer)
└── ActionPanel (PanelContainer, minimum size 430 × 150)
    └── MenuList (VBoxContainer)
        └── StartGameButton (Button, minimum size 320 × 72)
```

Assign `ActionPanel` a dedicated `StyleBoxFlat` through `theme_override_styles/panel`: semi-transparent deep navy background, `1px` antique-gold border, `32px` horizontal and `26px` vertical margins, and a soft black shadow. Set button text to `踏上巡礼`.

In `scripts/home/main_menu_screen.gd`, change only the on-ready lookup:

```gdscript
@onready var _start_game_button: Button = (
    $SafeArea/Layout/ActionBlock/ActionPanel/MenuList/StartGameButton
)
```

Do not modify `_ready()` or `_on_start_game_pressed()`.

- [ ] **Step 4: Re-run the focused home-menu test**

Run the Step 2 command. Expected: PASS; the new panel exists and two simulated clicks still emit one request while disabling the CTA.
### Task 2: Apply Readability Overlays and Complete Button States

**Files:**
- Modify: `tests/home_screen_flow_test.gd:24-70`
- Modify: `scenes/home/main_menu_screen.tscn:1-163`

**Interfaces:**
- Consumes: the `ActionPanel` hierarchy from Task 1 and existing title/subtitle labels.
- Produces: non-interactive readability overlays plus complete `normal`, `hover`, `pressed`, `disabled`, and `focus` styles for `StartGameButton`.

- [ ] **Step 1: Add failing visual-resource assertions**

Extend `_test_main_menu_structure_and_single_start_request()` with:

```gdscript
var atmosphere := menu.get_node_or_null("AtmosphereOverlay") as ColorRect
var top_gradient := menu.get_node_or_null("TopGradientOverlay") as TextureRect

_expect(
    atmosphere != null and atmosphere.mouse_filter == Control.MOUSE_FILTER_IGNORE,
    "menu has a non-interactive readability overlay"
)
_expect(
    top_gradient != null and top_gradient.mouse_filter == Control.MOUSE_FILTER_IGNORE,
    "menu has a non-interactive top readability gradient"
)
_expect(
    start != null and start.get_theme_stylebox("normal") != null
        and start.get_theme_stylebox("hover") != null
        and start.get_theme_stylebox("pressed") != null
        and start.get_theme_stylebox("disabled") != null
        and start.get_theme_stylebox("focus") != null,
    "pilgrimage CTA exposes all interaction-state styles"
)
_expect(start != null and start.get_theme_font_size("font_size") == 26,
    "pilgrimage CTA uses the approved restrained type scale")
_expect(logo != null and logo.get_theme_font_size("font_size") == 120,
    "menu title uses the approved home-page scale")
_expect(subtitle != null and subtitle.get_theme_font_size("font_size") == 26,
    "menu subtitle remains subordinate to the title")
```

- [ ] **Step 2: Run the focused home-menu test and confirm failure**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\home_screen_flow_test.gd
```

Expected: FAIL because no overlay nodes exist and the CTA has no `disabled` or `focus` stylebox.

- [ ] **Step 3: Implement the approved visual hierarchy and states**

In `scenes/home/main_menu_screen.tscn`:

1. Immediately after the background `TextureRect`, add full-rect `AtmosphereOverlay` (`ColorRect`) with `mouse_filter = 2` and low-alpha ink-black color.
2. Above it but below `SafeArea`, add full-rect `TopGradientOverlay` (`TextureRect`) with `mouse_filter = 2` and a vertical `GradientTexture2D`: translucent ink navy at top, transparent before the lower half.
3. Set `GameLogo` font size to `120` and `GameSubtitle` to `26`, retaining their existing gold color resources.
4. Replace the green `StyleBoxFlat` resources on `StartGameButton` with dark-navy resources. All use `6px` corner radii and consistent margins:

```text
normal:   navy-black matte base, dark-gold border, bone-white text
hover:    brighter gold border and slightly larger shadow
pressed:  darker base, reduced shadow, stronger inset appearance
disabled: desaturated blue-gray base, dark-copper border, muted text
focus:    transparent fill with a distinct fine gold focus outline
```

5. Keep `ActionPanel` darker and less saturated than the normal button. Do not add a `TextureButton`, shader, animation, or assets.

- [ ] **Step 4: Re-run the focused home-menu test**

Run the Step 2 command. Expected: PASS; overlays ignore input, all five CTA states exist, approved typography values are present, and routing behavior remains intact.
### Task 3: Run Regression and Godot Resource Validation

**Files:**
- Verify: `scenes/home/main_menu_screen.tscn`
- Verify: `scripts/home/main_menu_screen.gd`
- Verify: `tests/home_screen_flow_test.gd`
- Verify: `docs/superpowers/specs/2026-08-03-home-menu-art-direction-design.md`

**Interfaces:**
- Consumes: complete action-panel hierarchy and final button-state style resources.
- Produces: validated scene resources that preserve the main-menu route.

- [ ] **Step 1: Run the homepage flow regression**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\home_screen_flow_test.gd
```

Expected: PASS with exit code `0`; the menu-to-root-selection and debug-start paths remain unchanged.

- [ ] **Step 2: Run the responsive-layout regression**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\responsive_layout_scene_test.gd
```

Expected: PASS with exit code `0`; the centered menu still loads under the expandable canvas configuration.

- [ ] **Step 3: Validate Godot resource parsing**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --editor --quit
```

Expected: exit code `0` and no parse errors for `main_menu_screen.tscn` or `main_menu_screen.gd`.

- [ ] **Step 4: Check scoped diff quality**

```powershell
git diff --check
git diff -- scenes/home/main_menu_screen.tscn scripts/home/main_menu_screen.gd tests/home_screen_flow_test.gd docs/superpowers/specs/2026-08-03-home-menu-art-direction-design.md
git status --short
```

Expected: `git diff --check` has no output; scope contains only approved homepage resources, script-path adjustment, regression test, and documentation changes. Existing unrelated worktree changes remain untouched.