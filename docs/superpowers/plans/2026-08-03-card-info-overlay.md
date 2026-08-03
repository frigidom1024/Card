# Card Info Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display card hover details in a screen-space overlay that stays upright while the card entity rotates.

**Architecture:** Add a reusable `CardInfoOverlay` `CanvasLayer` beside `GameplayCanvas` in `GameManager`. Each gameplay `CardEntity` receives that overlay reference when created and asks it to show or hide a shared `CardInfo` panel; the overlay receives a screen-space card rectangle and owns edge-aware placement.

**Tech Stack:** Godot 4.7, GDScript, `.tscn` scenes, headless `SceneTree` script tests.

## Global Constraints

- Preserve the existing interaction rule: hide immediately when the pointer leaves the `CardEntity`; the panel itself ignores mouse input.
- Prefer the card’s right side, flip to its left when the right-side placement would leave the visible viewport, and clamp vertically inside fixed viewport margins.
- Do not inherit card transform, rotation, or `GameplayCanvas` scaling in the panel’s node hierarchy.
- Retain existing `CardInfo` card-detail content and visual styling; do not add selected-card, pinned-panel, mouse-following, animation, or comparison features.
- Do not create commits or alter unrelated existing untracked files.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `scripts/card/card_info_overlay.gd` | Owns a single shared `CardInfo`, computes panel placement in screen coordinates, and prevents stale deferred placement after a card hides. |
| `scenes/card_view/card_info_overlay.tscn` | Declares the independent `CanvasLayer` and hosts the existing `CardInfo` scene with mouse input ignored. |
| `scripts/card/card_entity.gd` | Converts its rotated `CardView` bounds into screen-space bounds and delegates show/hide requests to the injected overlay. |
| `scenes/card_view/card_entity.tscn` | Removes the inherited `CardInfo` child. |
| `scripts/game_manager.gd` | Owns the scene-level overlay reference and injects it into every newly created gameplay entity. |
| `scenes/game/game_manager.tscn` | Adds `CardInfoOverlay` as a sibling of `GameplayCanvas`, above gameplay and below modal UI. |
| `scripts/card/card_info.gd` | Remains a data renderer only; obsolete local-position hover helpers are removed. |
| `tests/card_info_overlay_test.gd` | Covers pure placement math and rotated-card integration behavior. |
| `tests/card_entity_display_mode_test.gd` | Keeps display-only cards from opening or leaving shared hover details visible. |

### Task 1: Add a Screen-Space Overlay and Placement Tests

**Files:**
- Create: `scripts/card/card_info_overlay.gd`
- Create: `scenes/card_view/card_info_overlay.tscn`
- Create: `tests/card_info_overlay_test.gd`
- Modify: `scripts/card/card_info.gd:1-109`

**Interfaces:**
- Consumes: `CardEntity`, `CardInstance`, and `scenes/card_view/card_info.tscn`.
- Produces: `class_name CardInfoOverlay` with `show_for_card(card: CardEntity) -> void`, `hide_for_card(card: CardEntity) -> void`, and `calculate_panel_position(card_rect: Rect2, panel_size: Vector2, viewport_size: Vector2) -> Vector2`.
- Invariant: `CardInfoOverlay/CardInfo` has `mouse_filter == Control.MOUSE_FILTER_IGNORE` and the overlay never rotates with a card.

- [ ] **Step 1: Write failing placement and overlay-behavior tests**

Create `tests/card_info_overlay_test.gd` as a `SceneTree` test that preloads `card_info_overlay.tscn` and `card_entity.tscn`. Add these expectations before the overlay exists:

```gdscript
func _test_right_side_and_left_flip() -> void:
    var overlay := CardInfoOverlayScene.instantiate() as CardInfoOverlay
    var panel_size := Vector2(220.0, 140.0)
    var viewport_size := Vector2(1280.0, 720.0)

    var right_position := overlay.calculate_panel_position(
        Rect2(Vector2(320.0, 200.0), Vector2(84.0, 150.0)), panel_size, viewport_size
    )
    _expect(right_position.x > 404.0, "panel prefers the card's right side")

    var left_position := overlay.calculate_panel_position(
        Rect2(Vector2(1180.0, 200.0), Vector2(84.0, 150.0)), panel_size, viewport_size
    )
    _expect(left_position.x + panel_size.x < 1180.0, "panel flips left near the viewport edge")
```

Also add an async integration test that adds the overlay and a `CardEntity` to `root`, assigns the overlay to `card.card_info_overlay`, rotates the card by `90.0` degrees, calls `card._on_mouse_entered()`, waits two `process_frame`s, then asserts:

```gdscript
var panel := overlay.get_node_or_null("CardInfo") as PanelContainer
_expect(panel != null and panel.visible, "hover shows the shared card info panel")
_expect(panel != null and panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "panel does not block card exit")
_expect(panel != null and is_zero_approx(panel.rotation), "panel remains upright after card rotation")
card._on_mouse_exited()
_expect(panel != null and not panel.visible, "card exit hides the shared panel immediately")
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_info_overlay_test.gd
```

Expected: non-zero exit because `card_info_overlay.tscn` and `CardInfoOverlay` do not exist.

- [ ] **Step 3: Implement `CardInfoOverlay` and move local hover ownership into it**

Create `scripts/card/card_info_overlay.gd` with these constants and methods:

```gdscript
class_name CardInfoOverlay
extends CanvasLayer

const GAP := 8.0
const VIEWPORT_MARGIN := 12.0

@onready var _card_info: PanelContainer = $CardInfo
var _active_card: CardEntity

func show_for_card(card: CardEntity) -> void:
    if card == null or card.card_instance == null or card.card_instance.card_data == null:
        return
    _active_card = card
    _card_info.set_card(card.card_instance)
    _card_info.show()
    await get_tree().process_frame
    if _active_card != card:
        return
    _card_info.position = calculate_panel_position(
        card.get_card_view_screen_rect(), _card_info.size, get_viewport().get_visible_rect().size
    )

func hide_for_card(card: CardEntity) -> void:
    if _active_card != card:
        return
    _active_card = null
    _card_info.hide()
```

Implement `calculate_panel_position` so it first tries `card_rect.end.x + GAP`, flips to `card_rect.position.x - GAP - panel_size.x` when the preferred candidate would exceed `viewport_size.x - VIEWPORT_MARGIN`, clamps X and Y to the same margin, and uses `card_rect.position.y - 4.0` as the preferred Y.

Create `scenes/card_view/card_info_overlay.tscn` with a root `CanvasLayer` on layer `5` and an instance of `card_info.tscn` named `CardInfo`. Set its initial `visible = false` and `mouse_filter = 2` (`MOUSE_FILTER_IGNORE`).

In `scripts/card/card_info.gd`, keep `set_card()` and rendering methods unchanged. Remove `show_as_floating()` and `hide_floating()` because the overlay now owns visibility and placement.

- [ ] **Step 4: Run the new test to verify the overlay implementation passes**

Run the same command from Step 2.

Expected: exit code `0`, including right-first placement, left flip, upright rendering, ignored mouse input, and immediate hide on card exit.

### Task 2: Wire Gameplay Cards to the Shared Overlay

**Files:**
- Modify: `scripts/card/card_entity.gd:51-171, 211-236, 284-322`
- Modify: `scenes/card_view/card_entity.tscn:1-40`
- Modify: `scripts/game_manager.gd:9-16, 121-134, 301-314`
- Modify: `scenes/game/game_manager.tscn:1-44`
- Modify: `tests/card_entity_display_mode_test.gd:19-75`

**Interfaces:**
- Consumes: `CardInfoOverlay.show_for_card(card)`, `CardInfoOverlay.hide_for_card(card)`, and `CardEntity.get_card_view_screen_rect() -> Rect2`.
- Produces: Every gameplay card from `GameManager` has `card_info_overlay` set before it is added to `HandArea`; preview-only cards remain safe when no overlay is assigned.
- Invariant: `CardEntity` has no `CardInfo` child and never positions a detail panel in local coordinates.

- [ ] **Step 1: Extend display-only coverage with a shared overlay assertion**

In `tests/card_entity_display_mode_test.gd`, preload `card_info_overlay.tscn`. In `_test_display_only_card_ignores_gameplay_interactions()`, add the overlay to `root`, assign it to the card before `set_display_only(true)`, and obtain its `CardInfo` child. After `card._on_mouse_entered()`, assert that the panel is still hidden:

```gdscript
_expect(not panel.visible, "display-only card does not show shared hover information")
```

Add a scene-tree assertion in the default gameplay-card test:

```gdscript
_expect(card.get_node_or_null("CardInfo") == null, "card entity no longer owns a transform-inherited info panel")
```

- [ ] **Step 2: Run the focused regression test to verify it fails**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_entity_display_mode_test.gd
```

Expected: failure while the scene still contains `CardInfo` and `CardEntity` has no overlay injection property.

- [ ] **Step 3: Delegate `CardEntity` hover details and preserve drag/zoom behavior**

In `scripts/card/card_entity.gd`:

1. Replace `@onready var _card_info: PanelContainer = $CardInfo` with `var card_info_overlay: CardInfoOverlay`.
2. Change `_show_info(show_info)` to call `card_info_overlay.show_for_card(self)` when true and `card_info_overlay.hide_for_card(self)` when false. Return safely when no overlay is injected, no card instance exists, or the card is display-only.
3. Add this helper to derive an axis-aligned screen rectangle from all four transformed `CardView` corners:

```gdscript
func get_card_view_screen_rect() -> Rect2:
    var transform := _card_view.get_global_transform_with_canvas()
    var points := [
        transform * Vector2.ZERO,
        transform * Vector2(_card_view.size.x, 0.0),
        transform * _card_view.size,
        transform * Vector2(0.0, _card_view.size.y),
    ]
    var min_point := points[0]
    var max_point := points[0]
    for point in points:
        min_point = min_point.min(point)
        max_point = max_point.max(point)
    return Rect2(min_point, max_point - min_point)
```

4. In `set_display_only(true)` and `_exit_tree()`, call `_show_info(false)` so a shared panel owned by this card is cleared safely.
5. Keep the existing `_start_drag()`, right-click, zoom-open, zoom-close, and state transitions; they already call `_show_info(false)` at the appropriate times.

In `scenes/card_view/card_entity.tscn`, remove the `card_info.tscn` external resource and the `CardInfo` child node.

In `scenes/game/game_manager.tscn`, add an external resource for `card_info_overlay.tscn` and add `CardInfoOverlay` as a `CanvasLayer` sibling after `GameplayCanvas` and before `EventModalLayer`.

In `scripts/game_manager.gd`, add:

```gdscript
@onready var card_info_overlay: CardInfoOverlay = $CardInfoOverlay
```

Immediately after each `card_manager.create_card_entity(...)` succeeds in both `_create_initial_player_cards()` and `add_card_to_hand()`, assign:

```gdscript
entity.card_info_overlay = card_info_overlay
```

- [ ] **Step 4: Run focused overlay and display-mode tests**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
$tests = @(
  'tests\card_info_overlay_test.gd',
  'tests\card_entity_display_mode_test.gd',
  'tests\card_zoom_overlay_test.gd',
  'tests\board_direction_test.gd'
)
foreach ($test in $tests) {
  & $godot --headless --path . --script $test
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

Expected: all tests exit with `0`; display-only previews remain inert, zoom remains a full-screen overlay, and board rotation rules remain unchanged.

### Task 3: Validate Scene Integration and Run Regression Checks

**Files:**
- Modify: `tests/card_info_overlay_test.gd` only if scene-level paths or asynchronous layout require an additional frame assertion discovered in Task 2.

**Interfaces:**
- Consumes: completed `GameManager/CardInfoOverlay/CardEntity` integration.
- Produces: verification that the overlay is layered independently from `GameplayCanvas` and does not regress existing UI/gameplay behavior.
- Invariant: CardInfoOverlay is a sibling of GameplayCanvas—not a descendant—and EventModalLayer remains above it.
- Invariant: `GameManager/CardInfoOverlay` is a sibling—not a descendant—of `GameManager/GameplayCanvas`; `EventModalLayer` remains above it.

- [ ] **Step 1: Add failing GameManager-layer assertions if absent**

In `tests/card_info_overlay_test.gd`, preload `game_manager.tscn`, add it to `root`, and assert:

```gdscript
var gameplay_canvas := manager.get_node_or_null("GameplayCanvas")
var overlay := manager.get_node_or_null("CardInfoOverlay") as CanvasLayer
var modal_layer := manager.get_node_or_null("EventModalLayer") as CanvasLayer
_expect(overlay != null and not gameplay_canvas.is_ancestor_of(overlay), "card info overlay is independent from gameplay scaling")
_expect(overlay != null and modal_layer != null and overlay.layer < modal_layer.layer, "event modals remain above card info")
```

If these assertions already exist from Task 1 or Task 2, do not duplicate them.

- [ ] **Step 2: Run the overlay integration test**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_info_overlay_test.gd
```

Expected: exit code `0`; the overlay is independent from gameplay scaling and below modal UI.

- [ ] **Step 3: Run relevant project regression tests and scene-load validation**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
$tests = @(
  'tests\card_info_overlay_test.gd',
  'tests\card_entity_display_mode_test.gd',
  'tests\card_zoom_overlay_test.gd',
  'tests\board_direction_test.gd',
  'tests\layout_config_test.gd',
  'tests\game_manager_run_setup_test.gd',
  'tests\gameplay_canvas_test.gd',
  'tests\responsive_layout_scene_test.gd'
)
foreach ($test in $tests) {
  & $godot --headless --path . --script $test
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& $godot --headless --path . --editor --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
git diff --check
```

Expected: every test and the headless editor load exit with `0`, and `git diff --check` reports no whitespace errors.

## Plan Self-Review

- **Spec coverage:** Task 1 implements a full-screen shared overlay, upright screen-space positioning, right-side preference, left-side flip, vertical clamping, and mouse input pass-through. Task 2 removes inherited local UI and injects the overlay into all runtime-created gameplay cards while preserving display-only, drag, right-click, and zoom rules. Task 3 asserts scene layering and runs related regressions.
- **Scope check:** The plan excludes pinned panels, fixed drawers, cursor-following UI, content restyling, mobile behavior, and all unrelated card gameplay changes.
- **Type consistency:** `CardInfoOverlay` declares the API consumed by `CardEntity`; `CardEntity.card_info_overlay` is injected by `GameManager`; `get_card_view_screen_rect()` supplies the `Rect2` required by overlay placement.
- **Placeholder scan:** No placeholder markers, undefined interfaces, omitted test commands, or deferred implementation steps remain.