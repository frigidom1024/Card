# Hand Tray Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blue debug hand-area rectangle with an editable, fixed-bottom pilgrim offering tray that displays the current hand count without changing card interactions.

**Architecture:** Add a `HandTray` `Control` scene under `GameplayCanvas`, behind `HandManager`. `HandTray` owns only visual sizing, palette, and its English hand-count label; `HandArea` emits count changes and `GameManager` forwards them after run initialization.

**Tech Stack:** Godot 4.7, GDScript, native `Control`/`Panel`/`Label` nodes, `StyleBoxFlat`, headless Godot scene tests.

## Global Constraints

- Keep all player-visible copy in English.
- Keep tray nodes on `MOUSE_FILTER_IGNORE`; they must not consume hover, drag, left-click, or right-click input.
- Preserve the existing centered horizontal `HandArea` layout, hover lift, hover scale, drag behavior, and combat behavior.
- Use the dark indigo, antique-gold, and bone-paper palette. Do not add raster art assets.
- Do not stage, commit, or create a branch unless the user explicitly requests it.

---

### Task 1: Create the Editable Hand Tray Component

**Files:**
- Create: `scripts/game/hand_tray.gd`
- Create: `scenes/game/hand_tray.tscn`
- Create: `tests/hand_tray_test.gd`

**Interfaces:**
- Produces: `class_name HandTray extends Control`.
- Produces: `func set_hand_count(current_count: int, max_count: int) -> void`.
- Consumes: `LayoutConfig.DESIGN_VIEWPORT_SIZE` for design-space placement.

- [ ] **Step 1: Write the failing component-scene test**

```gdscript
extends SceneTree

const HandTrayScene = preload("res://scenes/game/hand_tray.tscn")
var _failure_count := 0

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var tray := HandTrayScene.instantiate() as HandTray
	root.add_child(tray)
	await process_frame
	_expect(tray.mouse_filter == Control.MOUSE_FILTER_IGNORE, "hand tray passes pointer input to hand cards")
	_expect(tray.z_index < RenderPriority.CARD_BASE, "hand tray renders behind normal hand cards")
	_expect(tray.get_node_or_null("OuterTray") is Panel, "hand tray exposes an editable outer tray panel")
	_expect(tray.get_node_or_null("InnerLining") is Panel, "hand tray exposes a bone-paper inner lining")
	_expect(tray.get_node_or_null("TopTrim") is ColorRect, "hand tray exposes an antique-gold top trim")
	tray.set_hand_count(4, 10)
	var hand_count := tray.get_node_or_null("HandCount") as Label
	_expect(hand_count != null and hand_count.text == "HAND · 4 / 10", "hand tray renders English current and maximum hand count")
	tray.free()
	quit(1 if _failure_count > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
```

- [ ] **Step 2: Run the component test and verify it fails**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\hand_tray_test.gd
```

Expected: failure because the tray scene and class do not exist.

- [ ] **Step 3: Implement the tray script and editable scene**

Create `scripts/game/hand_tray.gd` with this public surface:

```gdscript
@tool
class_name HandTray
extends Control

@export_group("Layout")
@export_range(0.76, 0.82, 0.01) var width_ratio := 0.80
@export_range(210.0, 240.0, 1.0) var tray_height := 224.0
@export_range(0.0, 48.0, 1.0) var bottom_bleed := 20.0

@export_group("Palette")
@export var tray_color := Color("0a1220d9")
@export var lining_color := Color("9b90736b")
@export var trim_color := Color("b7964f99")
@export var show_side_ornaments := true

func set_hand_count(current_count: int, max_count: int) -> void:
	($HandCount as Label).text = "HAND · %d / %d" % [current_count, max_count]
```

Add a private `_apply_visuals()` called from `_ready()` and each export setter. It positions the tray at the design-space bottom center; calculates width from `width_ratio`; makes every child mouse-transparent; applies dark small-radius styling to `OuterTray`, muted bone-paper styling to `InnerLining`, and `trim_color` to the trim and clasp nodes.

Create `scenes/game/hand_tray.tscn` with this editable child hierarchy:

```text
HandTray (Control, script: hand_tray.gd, z_index: -1)
├── OuterTray (Panel)
├── InnerLining (Panel)
├── TopTrim (ColorRect)
├── LeftClasp (ColorRect)
├── RightClasp (ColorRect)
├── HandCount (Label, text: "HAND · 0 / 10")
└── FutureInfoAnchor (Control)
```

- [ ] **Step 4: Run the component test and verify it passes**

Run the Step 2 command. Expected: exit code `0` and every hierarchy, input, draw-order, and count-copy assertion passes.
### Task 2: Publish Hand Count Changes and Remove Debug Drawing

**Files:**
- Modify: `scripts/game/hand.gd:5-58`
- Modify: `tests/hand_tray_test.gd`

**Interfaces:**
- Produces: `signal hand_count_changed(current_count: int, max_count: int)` on `HandArea`.
- Produces: `func _emit_hand_count_changed() -> void` on `HandArea`.
- Consumes: `HandTray.set_hand_count(current_count, max_count)` in Task 3.

- [ ] **Step 1: Extend the failing test with actual hand mutations**

Add these preloads and test to `tests/hand_tray_test.gd`, then call it from `_run_tests()`:

```gdscript
const HandAreaScript = preload("res://scripts/game/hand.gd")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")

func _test_hand_count_signal_tracks_add_remove_and_clear() -> void:
	var hand := HandAreaScript.new() as HandArea
	var emitted_counts: Array[Vector2i] = []
	hand.hand_count_changed.connect(func(current_count: int, max_count: int) -> void:
		emitted_counts.append(Vector2i(current_count, max_count))
	)
	root.add_child(hand)
	var card := CardEntityScene.instantiate() as CardEntity
	_expect(hand.add_card(card, false), "hand accepts a card for count-change coverage")
	_expect(emitted_counts.back() == Vector2i(1, hand.max_hand_size), "adding a card emits the new hand count")
	_expect(hand.remove_card(card, false), "hand removes a card for count-change coverage")
	_expect(emitted_counts.back() == Vector2i(0, hand.max_hand_size), "removing a card emits the new hand count")
	_expect(hand.add_card(card, false), "hand can add the removed card before clear coverage")
	hand.clear_hand()
	_expect(emitted_counts.back() == Vector2i(0, hand.max_hand_size), "clearing the hand emits a zero hand count")
	hand.free()
```

- [ ] **Step 2: Run the focused test and verify it fails**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\hand_tray_test.gd
```

Expected: parser or assertion failure because `HandArea.hand_count_changed` does not exist.

- [ ] **Step 3: Implement notifications and delete the blue debug rectangle**

In `scripts/game/hand.gd`, add:

```gdscript
signal hand_count_changed(current_count: int, max_count: int)

func _emit_hand_count_changed() -> void:
	hand_count_changed.emit(cards.size(), max_hand_size)
```

Call `_emit_hand_count_changed()` after `cards.append(card)` and before `card_added.emit(card)`, after `cards.erase(card)` and before `card_removed.emit(card)`, and after `cards.clear()` in `clear_hand()`.

Delete the `show_debug` export plus the `_ready()` and `_draw()` implementation that renders the blue rectangle and Chinese debug label. Remove the now-unused `queue_redraw()` call from `rearrange_cards()`.

- [ ] **Step 4: Run the focused test and verify it passes**

Run the Step 2 command. Expected: exit code `0`; the tray and add/remove/clear count-notification assertions all pass.

### Task 3: Integrate the Tray Into the Gameplay Canvas

**Files:**
- Modify: `scenes/game/game_manager.tscn:3-24`
- Modify: `scripts/game_manager.gd:12-90`
- Modify: `tests/layout_config_test.gd:91-125`

**Interfaces:**
- Consumes: `HandTray.set_hand_count(current_count: int, max_count: int)`.
- Consumes: `HandArea.hand_count_changed(current_count: int, max_count: int)`.
- Produces: a `HandTray` instance at `$GameplayCanvas/HandTray`.

- [ ] **Step 1: Add failing GameManager integration assertions**

Add these assertions after `GameManager` enters the tree in `_test_game_manager_centering()` in `tests/layout_config_test.gd`:

```gdscript
var hand_tray := gm.get_node_or_null("GameplayCanvas/HandTray") as HandTray
_expect(hand_tray != null, "game manager owns a hand tray inside the gameplay canvas")
_expect(hand_tray != null and hand_tray.get_parent() == gameplay_canvas, "hand tray scales with the gameplay canvas")
_expect(hand_tray != null and hand_tray.z_index < RenderPriority.CARD_BASE, "hand tray stays behind hand cards")
_expect(hand_tray != null and hand_tray.mouse_filter == Control.MOUSE_FILTER_IGNORE, "hand tray does not block card input")
var hand_count := hand_tray.get_node_or_null("HandCount") as Label if hand_tray != null else null
_expect(
	hand_count != null and hand_count.text == "HAND · %d / %d" % [gm.hand_area.get_card_count(), gm.hand_area.max_hand_size],
	"game manager syncs the initial hand count to the tray"
)
```

- [ ] **Step 2: Run the integration test and verify it fails**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\layout_config_test.gd
```

Expected: failure because `GameplayCanvas/HandTray` is absent or unsynchronized.
- [ ] **Step 3: Add the scene instance and GameManager signal wiring**

In `scenes/game/game_manager.tscn`, add `res://scenes/game/hand_tray.tscn` as an external packed-scene resource. Add a `HandTray` instance immediately before `HandManager` under `GameplayCanvas` and set `z_index = -1`.

In `scripts/game_manager.gd`, add:

```gdscript
@onready var hand_tray: HandTray = $GameplayCanvas/HandTray

func _sync_hand_tray(
	current_count: int = hand_area.get_card_count(),
	max_count: int = hand_area.max_hand_size
) -> void:
	if hand_tray != null:
		hand_tray.set_hand_count(current_count, max_count)
```

After `_initialize_run_state()` succeeds in `_ready()`, connect and synchronize exactly once:

```gdscript
if not hand_area.hand_count_changed.is_connected(_sync_hand_tray):
	hand_area.hand_count_changed.connect(_sync_hand_tray)
_sync_hand_tray()
```

Do not alter `HandManager` positioning in `_center_layout()`; `HandTray` computes its own design-space geometry and inherits the same `GameplayCanvas` scale.

- [ ] **Step 4: Run integration and layout verification**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\hand_tray_test.gd
& $godot --headless --path . --script tests\layout_config_test.gd
```

Expected: both commands exit `0`; the tray is inside `GameplayCanvas`, stays behind cards, permits card input, and shows the starting hand count.

### Task 4: Final Regression and Editor Verification

**Files:**
- Verify only: `scenes/game/hand_tray.tscn`
- Verify only: `scenes/game/game_manager.tscn`
- Verify only: `scripts/game/hand_tray.gd`
- Verify only: `scripts/game/hand.gd`
- Verify only: `scripts/game_manager.gd`

- [ ] **Step 1: Run affected interaction regressions**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\layout_config_test.gd
& $godot --headless --path . --script tests\card_entity_display_mode_test.gd
& $godot --headless --path . --script tests\card_info_overlay_test.gd
& $godot --headless --path . --script tests\card_zoom_overlay_test.gd
```

Expected: each command exits `0`; hand layout remains responsive and card hover/right-click detail behavior remains intact.

- [ ] **Step 2: Verify project parsing and diff whitespace**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --editor --quit
git diff --check
```

Expected: Godot exits `0` without parse errors and `git diff --check` reports no whitespace errors.

## Self-Review

- **Spec coverage:** Task 1 creates the editable native-node tray, palette, lower-edge placement, ornaments, and English count label. Task 2 removes the debug rectangle and emits count updates for add, remove, and clear. Task 3 places the tray behind cards within the scaled gameplay canvas and connects runtime count updates. Task 4 verifies input, layout, project parsing, and whitespace.
- **Placeholder scan:** Every task includes concrete file paths, test commands, expected outcomes, and implementation details.
- **Type consistency:** `HandTray.set_hand_count(current_count: int, max_count: int)` is consumed consistently by `GameManager`; `HandArea.hand_count_changed(current_count: int, max_count: int)` is the only event used for runtime synchronization.