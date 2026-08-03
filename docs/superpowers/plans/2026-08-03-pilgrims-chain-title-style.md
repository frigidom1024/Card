# Pilgrim's Chain Gold-Foil Title Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the `PILGRIM'S CHAIN` main-menu title a readable gold-foil artistic-lettering treatment without adding a custom font resource.

**Architecture:** Keep the existing `GameLogo` and `GameSubtitle` `Label` nodes and use Godot theme overrides only. The flow test remains the contract for both title copy and the visual theme values, so no gameplay, layout, or menu routing code changes.

**Tech Stack:** Godot 4.7 `.tscn` theme overrides; GDScript headless scene-flow test.

## File Structure

- `scenes/home/main_menu_screen.tscn`: Owns `GameLogo` and `GameSubtitle` theme overrides.
- `tests/home_screen_flow_test.gd`: Verifies title copy and the gold-foil theme contract after scene instantiation.
- `docs/superpowers/specs/2026-08-03-pilgrims-chain-title-design.md`: Defines the approved built-in-font visual direction; no implementation logic belongs here.

## Global Constraints

- Keep the exact main-title copy `PILGRIM'S CHAIN`.
- Keep the exact subtitle copy `A CARD-CHAIN PILGRIMAGE`.
- Use only Godot's existing built-in font and label theme overrides; do not add font files, images, nodes, animations, or plugins.
- Do not modify menu layout, background, buttons, version label, signals, or game-entry routing.
- Main title uses bright antique gold, near-black brown outline, and amber-gold downward shadow; avoid forest green and neon glow.
- Subtitle uses a lower-saturation parchment gold with a thin dark outline.

---

### Task 1: Lock the Gold-Foil Theme Contract in the Menu Test

**Files:**
- Modify: `tests/home_screen_flow_test.gd:35-47`
- Test: `tests/home_screen_flow_test.gd`

**Interfaces:**
- Consumes: `GameLogo` and `GameSubtitle` `Label` nodes at `SafeArea/Layout/LogoBlock`.
- Produces: Headless assertions for the title copy, main-title colors and outline size, and subtitle color and outline size.

- [ ] **Step 1: Write the failing test**

Add these assertions after the existing title-copy assertions in `_test_main_menu_structure_and_single_start_request()`:

```gdscript
_expect(
	logo != null and logo.get_theme_color("font_color").is_equal_approx(Color(0.95, 0.69, 0.17, 1)),
	"menu title uses bright antique gold"
)
_expect(
	logo != null and logo.get_theme_color("font_outline_color").is_equal_approx(Color(0.16, 0.075, 0.018, 1)),
	"menu title uses near-black brown outline"
)
_expect(logo != null and logo.get_theme_constant("outline_size") == 4, "menu title uses a substantial gold-foil outline")
_expect(
	subtitle != null and subtitle.get_theme_color("font_color").is_equal_approx(Color(0.69, 0.50, 0.20, 1)),
	"menu subtitle uses parchment gold"
)
_expect(subtitle != null and subtitle.get_theme_constant("outline_size") == 1, "menu subtitle keeps a fine outline")
```

- [ ] **Step 2: Run the targeted test and verify it fails**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\home_screen_flow_test.gd
```

Expected: exit code `1` because the scene still has the prior ivory title color, prior dark-gold shadow values, and outline size `3`.

- [ ] **Step 3: Verify the test focuses only on approved styling**

Keep the existing button, signal, root-selection, and debug-entry assertions unchanged. Do not add tests for rendering screenshots, custom fonts, or unrelated menu nodes.

### Task 2: Apply the Built-In Gold-Foil Title Treatment

**Files:**
- Modify: `scenes/home/main_menu_screen.tscn:94-113`
- Test: `tests/home_screen_flow_test.gd`

**Interfaces:**
- Consumes: The exact color and outline assertions from Task 1.
- Produces: A `GameLogo` Label with gold-foil lettering and a `GameSubtitle` Label with parchment-gold supporting copy.

- [ ] **Step 1: Update `GameLogo` theme overrides**

Set these exact properties while keeping `font_size = 90`, title copy, centering, and the existing vertical shadow offset:

```ini
theme_override_colors/font_color = Color(0.95, 0.69, 0.17, 1)
theme_override_colors/font_outline_color = Color(0.16, 0.075, 0.018, 1)
theme_override_colors/font_shadow_color = Color(0.55, 0.25, 0.025, 0.85)
theme_override_constants/outline_size = 4
theme_override_constants/shadow_offset_x = 0
theme_override_constants/shadow_offset_y = 6
```

- [ ] **Step 2: Update `GameSubtitle` theme overrides**

Set the supporting label to parchment gold while preserving its existing text, font size `17`, and centering:

```ini
theme_override_colors/font_color = Color(0.69, 0.50, 0.20, 1)
theme_override_colors/font_outline_color = Color(0.08, 0.05, 0.02, 0.95)
theme_override_constants/outline_size = 1
```

- [ ] **Step 3: Run the targeted test and verify it passes**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\home_screen_flow_test.gd
```

Expected: exit code `0`.

- [ ] **Step 4: Load project resources and check the diff**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --editor --path . --quit
git diff --check
```

Expected: editor exits with code `0` and `git diff --check` reports no whitespace errors. Remove only untracked `.uid` files generated by this validation if they are not part of the intended change.

## Self-Review

- **Spec coverage:** Task 1 verifies the approved copy and theme contract; Task 2 applies bright antique gold, near-black brown outline, amber shadow, parchment-gold subtitle, and preserves the stated scope limits.
- **Placeholder scan:** No unresolved placeholder markers, unspecified colors, or deferred implementation details remain.
- **Type consistency:** Both tasks use Godot `Label` methods (`get_theme_color`, `get_theme_constant`) and the exact `GameLogo` / `GameSubtitle` node paths already used by the existing test.