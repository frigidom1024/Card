# Board Event Icon-First Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a single-cell board event card prioritize its icon while keeping a compact type badge, a single-line bottom name bar, and a readable no-icon fallback.

**Architecture:** Keep `BoardEvent` as a presentation-only `Control`. Add a small `TypeBadge` display for icon-backed events and retain `TypeLabel` as the large centered fallback for events without an icon. The scene owns geometry and styling; `event.gd` only toggles the presentation states from `EventData.icon`.

**Tech Stack:** Godot 4.7, GDScript, `.tscn` Control layout, existing SceneTree test runner.

## Global Constraints

- Keep `BoardEvent.setup(instance: EventInstance, cell_size: int)` board-local positioning and size behavior unchanged.
- Keep `event_selected(instance)` and all unbound/resolved selection safeguards unchanged.
- Do not add game-flow, Board, combat, shop, treasure, or asset-generation dependencies.
- Use real instantiated `BoardEvent` nodes in tests; do not test scene text or mock UI nodes.
- A configured `EventData.icon` shows `Icon` plus the small `TypeBadge`; no icon shows the centered `TypeLabel` fallback.

---

### Task 1: Build and verify the icon-first card presentation

**Files:**
- Modify: `scenes/game/event.tscn`
- Modify: `scripts/game/event.gd`
- Modify: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes: `BoardEvent.setup(instance: EventInstance, cell_size: int)`, `EventData.icon`, and the root nodes already instantiated by `event.tscn`.
- Produces: `TypeBadge` and `NameBar` scene nodes; `_refresh()` toggles `Icon`, `TypeBadge`, and fallback `TypeLabel` without changing event selection behavior.

- [ ] **Step 1: Write the failing scene-level test**

Extend `_test_board_event_binding()` in `tests/combat_model_test.gd` after creating `board_event`:

```gdscript
var name_bar := board_event.get_node_or_null("NameBar") as ColorRect
var type_badge := board_event.get_node_or_null("TypeBadge") as Label
var icon := board_event.get_node("Icon") as TextureRect
var type_label := board_event.get_node("TypeLabel") as Label
var name_label := board_event.get_node("NameLabel") as Label
_expect(name_bar != null, "event cards have a bottom name bar")
_expect(type_badge != null, "icon-backed event cards have a type badge")
_expect(name_label.autowrap_mode == TextServer.AUTOWRAP_OFF, "event names stay on one line")
_expect(name_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "long event names are truncated with an ellipsis")

template.icon = GradientTexture2D.new()
board_event.setup(instance, 80)
_expect(icon.visible, "event icons are shown when configured")
_expect(type_badge != null and type_badge.visible, "icon-backed events show a compact type badge")
_expect(not type_label.visible, "icon-backed events hide the centered fallback marker")

template.icon = null
board_event.setup(instance, 80)
_expect(not icon.visible, "events without icons hide the icon region")
_expect(type_badge != null and not type_badge.visible, "events without icons hide the compact type badge")
_expect(type_label.visible, "events without icons show the centered fallback marker")
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/combat_model_test.gd
```

Expected: scene-level assertions fail because `NameBar` and `TypeBadge` do not exist, `NameLabel` is still wrapping, and `_refresh()` has no `TypeBadge` state.

- [ ] **Step 3: Implement the minimal icon-first scene layout**

In `scenes/game/event.tscn`:

1. Resize `Icon` to occupy the central portion of the card, leaving room for a bottom title bar.
2. Add `TypeBadgeBackground` (`ColorRect`) and `TypeBadge` (`Label`) at the top-left; render the marker small and white over a translucent dark background.
3. Keep `TypeLabel` as the no-icon fallback: center it above the name bar and increase its font size so it reads as the primary symbol.
4. Add `NameBar` (`ColorRect`) above the bottom edge with a translucent dark color; move `NameLabel` into the same horizontal region.
5. Set `NameLabel.autowrap_mode = 0`, `NameLabel.text_overrun_behavior = 3`, centered alignment, and a compact font size. Its rectangle must be 1 line tall inside `NameBar`.
6. Keep `ResolvedOverlay` and `SelectButton` full-card and topmost, preserving their existing input behavior.

In `scripts/game/event.gd`:

```gdscript
@onready var type_badge_background: ColorRect = $TypeBadgeBackground
@onready var type_badge: Label = $TypeBadge
```

Replace the current `TypeLabel` visibility block in `_refresh()` with:

```gdscript
var has_icon := icon.texture != null
icon.visible = has_icon
type_badge_background.visible = has_icon
type_badge.visible = has_icon
type_badge.text = _get_type_marker(data.event_type) if data else "?"
type_label.visible = not has_icon
type_label.text = _get_type_marker(data.event_type) if data else "?"
```

Do not change `setup()`, `_on_select_button_pressed()`, or any selection-state behavior.

- [ ] **Step 4: Run focused and visual startup verification**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/combat_model_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . res://scenes/game/event.tscn --quit-after 2
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --quit-after 10
git diff --check -- scenes/game/event.tscn scripts/game/event.gd tests/combat_model_test.gd
```

Expected: all Godot commands exit `0`, their output contains no `Parse Error:`, `SCRIPT ERROR:`, or `Failed to load script`, and whitespace validation is clean.

- [ ] **Step 5: Commit**

```powershell
git add -- scenes/game/event.tscn scripts/game/event.gd tests/combat_model_test.gd
git commit -m "feat: refine board event card layout"
```
