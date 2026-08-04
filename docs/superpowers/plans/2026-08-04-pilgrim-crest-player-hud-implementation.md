# Pilgrim Crest Player HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the reusable, combat-first Pilgrim Crest HUD to gameplay so vitality and faith are always readable without exposing temporary defense or blocking card input.

**Architecture:** A new `PilgrimCrestHud` Control scene owns all presentation, Inspector-editable styling, status collapsing, and mouse transparency. `GameManager` retains runtime ownership of `CombatStats` and `FaithService`; it only pushes the current HP, maximum HP, faith, and optional temporary-status string into the HUD. `RenderPriority` provides one named layer value so the HUD stays above the board background and below card and modal surfaces.

**Tech Stack:** Godot 4.7, GDScript, Control/Panel/Label/ProgressBar nodes, `StyleBoxFlat`, existing headless SceneTree tests.

## Global Constraints

- Use native Godot controls and `StyleBoxFlat`; do not add raster art assets.
- Keep all HUD copy in English.
- Do not display persistent `DEF`; temporary defense remains combat-resolution feedback only.
- Put the HUD under `GameplayCanvas` so it uses existing 1920×1080 design-space scaling.
- Set every HUD Control node to `Control.MOUSE_FILTER_IGNORE` so it cannot block board or card interactions.
- Keep the HUD above `RenderPriority.BOARD_BACKGROUND` and below card-info, card-zoom, drag, and modal layers.
- Preserve the user’s unrelated working-tree changes; do not stage or commit unless they explicitly request it.

---

## File Structure

| Path | Responsibility |
|---|---|
| `scripts/game/pilgrim_crest_hud.gd` | Presentation-only HUD API, Inspector properties, native-style application, and status-row visibility. |
| `scenes/game/pilgrim_crest_hud.tscn` | Reusable Control hierarchy for the plaque, labels, vitality bar, faith seal, and optional status row. |
| `scripts/game/render_priority.gd` | Named `PLAYER_HUD` z-index constant. |
| `scripts/game_manager.gd` | Pushes existing HP and faith state to the scene HUD, removes the legacy ad hoc `FaithHud`, and exposes a status pass-through. |
| `scenes/game/game_manager.tscn` | Instances the HUD under `GameplayCanvas`. |
| `tests/pilgrim_crest_hud_test.gd` | Scene-level presentation and mouse-transparency coverage. |
| `tests/game_manager_faith_test.gd` | Migrates faith assertions from the legacy Chinese `FaithLabel` to the English faith seal. |
| `tests/layout_config_test.gd` | Verifies parentage, design-space placement, z-order, and input transparency in a live GameManager scene. |

### Task 1: Build the Reusable Pilgrim Crest HUD Scene

**Files:**
- Create: `tests/pilgrim_crest_hud_test.gd`
- Create: `scripts/game/pilgrim_crest_hud.gd`
- Create: `scenes/game/pilgrim_crest_hud.tscn`

**Interfaces:**
- Produces: `class_name PilgrimCrestHud extends Control`.
- Produces: `set_vitality(current_hp: int, max_hp: int) -> void`.
- Produces: `set_faith(current_faith: int) -> void`.
- Produces: `set_temporary_status(status_text: String) -> void`.
- Produces: `set_display_context(title: String, subtitle: String, map_name: String) -> void`.
- Consumed later by: `GameManager` through `$GameplayCanvas/PilgrimCrestHud`.

- [ ] **Step 1: Write the failing HUD scene test**

Create `tests/pilgrim_crest_hud_test.gd` as a `SceneTree` test that preloads `res://scenes/game/pilgrim_crest_hud.tscn`, instantiates it below `root`, and exercises the public scene API:

```gdscript
extends SceneTree

const PilgrimCrestHudScene = preload("res://scenes/game/pilgrim_crest_hud.tscn")

var _failure_count := 0

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var hud := PilgrimCrestHudScene.instantiate() as PilgrimCrestHud
	root.add_child(hud)
	await process_frame

	hud.set_display_context("PILGRIM", "LAST KNIGHT", "RIBWOOD")
	hud.set_vitality(34, 50)
	hud.set_faith(3)
	hud.set_temporary_status("")

	_expect((hud.get_node("VitalityValue") as Label).text == "34 / 50", "HUD formats vitality")
	_expect((hud.get_node("VitalityBar") as ProgressBar).value == 34.0, "HUD fills vitality bar")
	_expect((hud.get_node("FaithSeal/FaithValue") as Label).text == "FAITH · 3", "HUD formats faith")
	_expect(not (hud.get_node("StatusRow") as Control).visible, "empty status collapses status row")

	hud.set_temporary_status("CURSE · BONE CHILL")
	_expect((hud.get_node("StatusRow") as Control).visible, "active status shows status row")
	_expect((hud.get_node("StatusRow/StatusLabel") as Label).text == "CURSE · BONE CHILL", "HUD keeps supplied status copy")
	_expect(_all_controls_ignore_mouse(hud), "HUD controls do not capture card input")

	hud.queue_free()
	await process_frame
	quit(0 if _failure_count == 0 else 1)

func _all_controls_ignore_mouse(node: Node) -> bool:
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child in node.get_children():
		if not _all_controls_ignore_mouse(child):
			return false
	return true

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
```

- [ ] **Step 2: Run the scene test and verify it fails**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\pilgrim_crest_hud_test.gd
```

Expected: non-zero exit because the Pilgrim Crest scene and class do not exist.

- [ ] **Step 3: Add the presentation-only HUD script**

Create `scripts/game/pilgrim_crest_hud.gd` with `@tool`, `class_name PilgrimCrestHud`, and exported groups matching the design spec:

```gdscript
@tool
class_name PilgrimCrestHud
extends Control

@export_group("Content")
@export var pilgrim_title := "PILGRIM"
@export var pilgrim_subtitle := "LAST KNIGHT"
@export var map_name := "RIBWOOD"

@export_group("Layout")
@export var outer_margin := Vector2(40, 36)
@export_range(250.0, 290.0, 1.0) var plaque_width := 270.0

func set_display_context(title: String, subtitle: String, location_name: String) -> void:
	pilgrim_title = title
	pilgrim_subtitle = subtitle
	map_name = location_name
	_apply_visuals()

func set_vitality(current_hp: int, max_hp: int) -> void:
	var safe_max_hp := max(1, max_hp)
	($VitalityValue as Label).text = "%d / %d" % [current_hp, safe_max_hp]
	($VitalityBar as ProgressBar).max_value = safe_max_hp
	($VitalityBar as ProgressBar).value = clampi(current_hp, 0, safe_max_hp)

func set_faith(current_faith: int) -> void:
	($FaithSeal/FaithValue as Label).text = "FAITH · %d" % current_faith

func set_temporary_status(status_text: String) -> void:
	var visible_status := status_text.strip_edges()
	($StatusRow as Control).visible = not visible_status.is_empty()
	($StatusRow/StatusLabel as Label).text = visible_status
```

Finish `_apply_visuals()` so it: anchors the plaque at `outer_margin`; applies indigo-black outer, gray-bone inset, antique-gold trim, deep-crimson vitality colors through `StyleBoxFlat`; applies the exported English content; and recursively assigns `MOUSE_FILTER_IGNORE` to the HUD and all Control descendants. Make every palette value an exported property with a setter that calls `_apply_visuals()`.

- [ ] **Step 4: Create the native-node scene hierarchy**

Create `scenes/game/pilgrim_crest_hud.tscn` rooted at `PilgrimCrestHud` and wire these exact node paths required by the test and script:

```text
PilgrimCrestHud (Control)
├── OuterPlaque (Panel)
├── BoneInset (Panel)
├── CrestGlyph (Label)
├── IdentityLabel (Label)
├── SubtitleLabel (Label)
├── MapLabel (Label)
├── VitalityValue (Label)
├── VitalityBar (ProgressBar)
├── FaithSeal (Panel)
│   └── FaithValue (Label)
└── StatusRow (Panel)
    └── StatusLabel (Label)
```

Use a 270 px-wide compact plaque with a 32–48 px top-left design-space margin. The status row begins hidden in the scene. Set `show_percentage = false` on `VitalityBar`; do not add a defense node, label, or icon.

- [ ] **Step 5: Run the focused HUD test and inspect editor parsing**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\pilgrim_crest_hud_test.gd
& $godot --headless --path . --editor --quit
```

Expected: both commands exit `0`; the scene is parseable, displays HP and faith text through its public API, collapses the empty status row, and captures no input.

### Task 2: Replace the Legacy Faith HUD with Runtime Synchronization

**Files:**
- Modify: `scripts/game_manager.gd:12-76`
- Modify: `scripts/game_manager.gd:170-191`
- Modify: `scripts/game_manager.gd:436-441`
- Modify: `tests/game_manager_faith_test.gd:34-54`
- Create: `tests/game_manager_player_hud_test.gd`

**Interfaces:**
- Consumes: `PilgrimCrestHud.set_vitality(current_hp: int, max_hp: int) -> void`.
- Consumes: `PilgrimCrestHud.set_faith(current_faith: int) -> void`.
- Consumes: `PilgrimCrestHud.set_temporary_status(status_text: String) -> void`.
- Produces: `GameManager.set_player_temporary_status(status_text: String) -> void`.
- Produces: `GameManager._sync_pilgrim_crest() -> void`.

- [ ] **Step 1: Add failing GameManager HUD integration coverage**

Create `tests/game_manager_player_hud_test.gd`, using the same `GameManagerScene`, `RevivalDeck`, `root.add_child(manager)`, and `await process_frame` setup from `tests/game_manager_faith_test.gd`. Add tests for initial runtime sync, combat HP refresh, faith refresh, and status pass-through:

```gdscript
func _test_game_manager_syncs_pilgrim_crest() -> void:
	var manager := await _make_game_manager()
	var hud := manager.get_node_or_null("GameplayCanvas/PilgrimCrestHud") as PilgrimCrestHud
	_expect(hud != null, "game manager owns a Pilgrim Crest HUD")
	_expect(
		hud != null and (hud.get_node("VitalityValue") as Label).text == "%d / %d" % [manager.player_stats.hp, manager.player_stats.max_hp],
		"HUD starts with runtime vitality"
	)
	_expect(hud != null and (hud.get_node("FaithSeal/FaithValue") as Label).text == "FAITH · 3", "HUD starts with runtime faith")
	_expect(manager.find_child("FaithHud", true, false) == null, "legacy FaithHud is removed")
	_cleanup_manager(manager)

func _test_player_hud_syncs_updates_and_status() -> void:
	var manager := await _make_game_manager()
	var hud := manager.get_node("GameplayCanvas/PilgrimCrestHud") as PilgrimCrestHud
	var after_combat := CombatStats.new()
	after_combat.max_hp = manager.player_stats.max_hp
	after_combat.hp = manager.player_stats.hp - 4
	manager._apply_player_combat_state(after_combat)
	_expect((hud.get_node("VitalityValue") as Label).text == "%d / %d" % [after_combat.hp, after_combat.max_hp], "HUD refreshes after combat")
	manager._on_faith_changed(2)
	_expect((hud.get_node("FaithSeal/FaithValue") as Label).text == "FAITH · 2", "HUD refreshes after faith signal")
	manager.set_player_temporary_status("CURSE · BONE CHILL")
	_expect((hud.get_node("StatusRow") as Control).visible, "manager exposes temporary status")
	manager.set_player_temporary_status("")
	_expect(not (hud.get_node("StatusRow") as Control).visible, "empty manager status clears row")
	_cleanup_manager(manager)
```

Include `_make_game_manager()`, `_cleanup_manager()`, `_expect()`, and the SceneTree test runner using the exact patterns in `tests/game_manager_faith_test.gd`.

- [ ] **Step 2: Run the integration tests and verify they fail**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\game_manager_player_hud_test.gd
& $godot --headless --path . --script tests\game_manager_faith_test.gd
```

Expected: the new test fails because the GameManager scene has no Pilgrim Crest HUD, and the existing faith test still expects the removed Chinese `FaithLabel`.

- [ ] **Step 3: Wire the existing runtime values into the HUD**

In `scripts/game_manager.gd`, replace the `FaithHud` CanvasLayer and `_faith_label` implementation with one on-ready HUD reference and these methods:

```gdscript
@onready var pilgrim_crest_hud: PilgrimCrestHud = $GameplayCanvas/PilgrimCrestHud

func _sync_pilgrim_crest() -> void:
	if pilgrim_crest_hud == null:
		return
	if player_stats != null:
		pilgrim_crest_hud.set_vitality(player_stats.hp, player_stats.max_hp)
	pilgrim_crest_hud.set_faith(_faith_service.get_faith())

func set_player_temporary_status(status_text: String) -> void:
	if pilgrim_crest_hud != null:
		pilgrim_crest_hud.set_temporary_status(status_text)

func _on_faith_changed(current_faith: int) -> void:
	faith_changed.emit(current_faith)
	if pilgrim_crest_hud != null:
		pilgrim_crest_hud.set_faith(current_faith)
```

After `_initialize_run_state()` succeeds in `_ready()`, call `_sync_pilgrim_crest()` once. Keep the existing `FaithService.faith_changed` signal connection, but remove `_create_faith_hud()`, `_update_faith_hud()`, the `FaithHud` CanvasLayer, and the Chinese `FaithLabel`. After assigning `player_stats.hp` in `_apply_player_combat_state()`, call `_sync_pilgrim_crest()` so HP refreshes after victory, retreat, or defeat results. Do not add a persistent defense field or synchronize `player_stats.defense` to the HUD.

- [ ] **Step 4: Migrate faith regression assertions to the new English faith seal**

In `tests/game_manager_faith_test.gd`, replace both legacy label lookups with:

```gdscript
var faith_value := manager.get_node_or_null("GameplayCanvas/PilgrimCrestHud/FaithSeal/FaithValue") as Label
_expect(
	faith_value != null and faith_value.text == "FAITH · 2",
	"Pilgrim Crest faith seal refreshes after manual chain removal"
)
```

For the initial-readout case, assert `"FAITH · 3"`. Leave all faith-debt, tail-return, and monster-spawn behavior assertions unchanged.

- [ ] **Step 5: Run focused runtime tests**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\game_manager_player_hud_test.gd
& $godot --headless --path . --script tests\game_manager_faith_test.gd
```

Expected: both commands exit `0`; HP and faith are rendered from their existing services, the legacy HUD is absent, and status text remains purely display state.

### Task 3: Integrate the HUD into GameplayCanvas and Rendering Priority

**Files:**
- Modify: `scripts/game/render_priority.gd:4-11`
- Modify: `scenes/game/game_manager.tscn:14-33`
- Modify: `tests/layout_config_test.gd:91-125`

**Interfaces:**
- Produces: `RenderPriority.PLAYER_HUD := -5`.
- Produces: `$GameplayCanvas/PilgrimCrestHud` scene instance.
- Consumes: `PilgrimCrestHud` scene from Task 1.
- Consumed later by: card and overlay systems retain their existing priority values unchanged.

- [ ] **Step 1: Add failing scaled-layout assertions**

In `tests/layout_config_test.gd`, preload `res://scripts/game/render_priority.gd` if the file does not already resolve `RenderPriority`. Add this block after the existing `GameplayCanvas` and `HandTray` checks in `_test_game_manager_centering()`:

```gdscript
var pilgrim_hud := gm.get_node_or_null("GameplayCanvas/PilgrimCrestHud") as PilgrimCrestHud
_expect(pilgrim_hud != null, "game manager owns a Pilgrim Crest inside GameplayCanvas")
_expect(pilgrim_hud != null and pilgrim_hud.get_parent() == gameplay_canvas, "Pilgrim Crest scales with GameplayCanvas")
_expect(pilgrim_hud != null and pilgrim_hud.z_index == RenderPriority.PLAYER_HUD, "Pilgrim Crest uses the named HUD priority")
_expect(pilgrim_hud != null and pilgrim_hud.z_index > RenderPriority.BOARD_BACKGROUND, "Pilgrim Crest stays above board background")
_expect(pilgrim_hud != null and pilgrim_hud.z_index < RenderPriority.CARD_INFO_OVERLAY, "Pilgrim Crest stays below card information")
_expect(pilgrim_hud != null and pilgrim_hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Pilgrim Crest does not block card input")
```

- [ ] **Step 2: Run the layout test and verify it fails**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\layout_config_test.gd
```

Expected: failure because the scene instance and `PLAYER_HUD` priority constant do not exist.

- [ ] **Step 3: Add the named priority and scene instance**

In `scripts/game/render_priority.gd`, add the explicit constant between board decoration and cards:

```gdscript
const PLAYER_HUD := -5
```

In `scenes/game/game_manager.tscn`, add `res://scenes/game/pilgrim_crest_hud.tscn` as an external packed-scene resource. Instance it under `GameplayCanvas` before `HandTray`, set `z_index = -5`, and name the node `PilgrimCrestHud`:

```text
GameplayCanvas
├── PilgrimCrestHud (instance, z_index = -5)
├── HandTray (instance, z_index = -1)
├── HandManager
├── CardManager
├── DragLayer
└── Board
```

Do not alter existing `HandTray`, board, hand, drag, or modal z-index values.

- [ ] **Step 4: Run the layout tests at normal and subviewport sizes**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\layout_config_test.gd
& $godot --headless --path . --script tests\pilgrim_crest_hud_test.gd
```

Expected: both commands exit `0`; the HUD remains in design space at normal and subviewport sizes, and no part of the Control tree consumes pointer input.

### Task 4: Final Regression and Editor Verification

**Files:**
- Verify: `scenes/game/pilgrim_crest_hud.tscn`
- Verify: `scripts/game/pilgrim_crest_hud.gd`
- Verify: `scenes/game/game_manager.tscn`
- Verify: `scripts/game/game_manager.gd`
- Verify: `scripts/game/render_priority.gd`
- Verify: `tests/pilgrim_crest_hud_test.gd`
- Verify: `tests/game_manager_player_hud_test.gd`
- Verify: `tests/game_manager_faith_test.gd`
- Verify: `tests/layout_config_test.gd`

**Interfaces:**
- Consumes: all public methods and scene paths created in Tasks 1–3.
- Produces: a parseable game scene with verified non-blocking player HUD behavior.

- [ ] **Step 1: Run focused gameplay UI regressions**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\pilgrim_crest_hud_test.gd
& $godot --headless --path . --script tests\game_manager_player_hud_test.gd
& $godot --headless --path . --script tests\game_manager_faith_test.gd
& $godot --headless --path . --script tests\layout_config_test.gd
& $godot --headless --path . --script tests\hand_tray_test.gd
```

Expected: every command exits `0`; player values update, no persistent defense is introduced, the tray remains unchanged, and the HUD does not block interaction.

- [ ] **Step 2: Run card-interaction regressions**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_entity_display_mode_test.gd
& $godot --headless --path . --script tests\card_info_overlay_test.gd
& $godot --headless --path . --script tests\card_zoom_overlay_test.gd
```

Expected: every command exits `0`; hover cards, right-click information, zoom overlay, and display-only card behavior retain their current input and z-order behavior.

- [ ] **Step 3: Verify project parsing and patch hygiene**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --editor --quit
git diff --check
```

Expected: Godot exits `0` without scene or script parse errors, and `git diff --check` reports no whitespace errors. Do not stage or commit the result unless the user explicitly asks.

## Self-Review

- **Spec coverage:** Task 1 provides the native scene, Inspector tuning, English copy, vitality display, faith seal, optional status collapse, and mouse transparency. Task 2 removes the legacy faith-only HUD, synchronizes existing HP and faith data, keeps defense out, and adds a display-only status pass-through. Task 3 places the scene in the scaled gameplay canvas with a named z-index below card information. Task 4 verifies the new HUD, existing faith behavior, design-space layout, hand tray, card hover, right-click information, zoom overlay, and project parsing.
- **Placeholder scan:** The plan contains concrete scene paths, scripts, public method signatures, test cases, Godot commands, and expected results. No unfinished marker, deferred implementation, or undefined interface remains.
- **Type consistency:** `PilgrimCrestHud.set_vitality(current_hp: int, max_hp: int)`, `set_faith(current_faith: int)`, and `set_temporary_status(status_text: String)` are defined in Task 1 and consumed under the same names in Tasks 2–4. `GameManager.set_player_temporary_status(status_text: String)` is defined and tested in Task 2. `RenderPriority.PLAYER_HUD` is defined in Task 3 and asserted under the same name.
