# Board Event Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `event.tscn` into a reusable `Control` node that renders one `EventInstance` at its board location and emits a selection signal.

**Architecture:** `BoardEvent` is a presentation component placed under `Board`. Its `setup(instance, cell_size)` method converts grid data into the `Control` position and size, then refreshes labels, icon fallback, colour and resolved state. It emits `event_selected` for the surrounding board or game manager to route into combat, shop or treasure flows.

**Tech Stack:** Godot 4.7, GDScript, `.tscn` scenes, existing `EventData` / `EventInstance` resources.

## Global Constraints

- Keep `event.tscn` rooted at `Control`; use top-left anchors rather than full-screen anchors.
- Do not modify combat, shop, treasure or board placement behaviour.
- The scene must work when it is a direct child of `Board` and receives board-local coordinates.
- Unbound and resolved nodes must never emit `event_selected`.
- Use existing `EventData.icon` when present; otherwise show a readable type marker.

---

## File Structure

- Create: `scripts/game/event.gd` — `BoardEvent` binding interface, rendering state and selection signal.
- Modify: `scenes/game/event.tscn` — compact `Control` tree with clickable background, text, icon fallback and completion overlay.
- Modify: `tests/combat_model_test.gd` — scene-level regression checks in the existing headless test runner.

### Task 1: Define the BoardEvent binding contract

**Files:**
- Create: `scripts/game/event.gd`
- Modify: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes: `EventInstance`, `EventData`, `EventMonsterContent`, and an integer `cell_size`.
- Produces: `class_name BoardEvent`, `signal event_selected(instance: EventInstance)`, and `func setup(instance: EventInstance, cell_size: int) -> void`.

- [ ] **Step 1: Write the failing test**

Add this helper and assertion block to `tests/combat_model_test.gd` before `_expect`:

```gdscript
const BoardEventScene = preload("res://scenes/game/event.tscn")

func _test_board_event_binding() -> void:
    var template := EventData.new()
    template.event_id = "forest_wolf"
    template.event_type = EventData.EventType.MONSTER
    template.size = Vector2i(2, 1)
    var instance := template.create_instance(Vector2i(2, 3))
    var board_event := BoardEventScene.instantiate() as BoardEvent
    root.add_child(board_event)
    board_event.setup(instance, 80)
    _expect(board_event.position == Vector2(160, 240), "event aligns to its board origin")
    _expect(board_event.size == Vector2(160, 80), "event spans its configured board cells")
    _expect(board_event.event_instance == instance, "event keeps the supplied runtime instance")
    board_event.queue_free()
```

Call `_test_board_event_binding()` from `_init()` after the existing event-library checks.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/combat_model_test.gd --log-file "$env:TEMP\monocard-board-event-red.log"
```

Expected: the test fails because `BoardEvent` and `setup` do not exist yet.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/game/event.gd`:

```gdscript
class_name BoardEvent
extends Control

signal event_selected(instance: EventInstance)

var event_instance: EventInstance
var _cell_size := 80

func setup(instance: EventInstance, cell_size: int) -> void:
    event_instance = instance
    _cell_size = cell_size
    position = Vector2(instance.origin * cell_size)
    size = Vector2(instance.get_size() * cell_size)
    custom_minimum_size = size
    if is_node_ready():
        _refresh()

func _ready() -> void:
    _refresh()

func _refresh() -> void:
    pass
```

Attach it to the root of `scenes/game/event.tscn`. Do not add game-flow dependencies.

- [ ] **Step 4: Run the test to verify it passes**

Run the same command from Step 2. Expected: exit code `0` and no `SCRIPT ERROR` lines.

- [ ] **Step 5: Commit**

```powershell
git add -- scripts/game/event.gd scenes/game/event.tscn tests/combat_model_test.gd
git commit -m "feat: add board event binding"
```

### Task 2: Render state and forward input through a signal

**Files:**
- Modify: `scripts/game/event.gd`
- Modify: `scenes/game/event.tscn`
- Modify: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes: `BoardEvent.setup(instance: EventInstance, cell_size: int)` from Task 1.
- Produces: `_refresh() -> void`, `event_selected(instance: EventInstance)`, and a clickable `Button` named `SelectButton`.

- [ ] **Step 1: Write the failing test**

Extend `_test_board_event_binding()` after `setup`:

```gdscript
var selected_instance: EventInstance = null
board_event.event_selected.connect(func(selected: EventInstance) -> void:
    selected_instance = selected
)
board_event.get_node("SelectButton").pressed.emit()
_expect(selected_instance == instance, "event click emits its runtime instance")
instance.resolve()
board_event.setup(instance, 80)
selected_instance = null
board_event.get_node("SelectButton").pressed.emit()
_expect(selected_instance == null, "resolved events cannot be selected again")
_expect(board_event.get_node("ResolvedOverlay").visible, "resolved events show their completion state")
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/combat_model_test.gd --log-file "$env:TEMP\monocard-board-event-interaction-red.log"
```

Expected: the scene is missing `SelectButton` and `ResolvedOverlay`.

- [ ] **Step 3: Write the minimal implementation**

Replace the full-screen layout in `scenes/game/event.tscn` with this named structure:

```text
Event (Control, script = event.gd)
├── Background (Panel)
├── Icon (TextureRect)
├── TypeLabel (Label)
├── NameLabel (Label)
├── ResolvedOverlay (ColorRect)
└── SelectButton (Button)
```

In `scripts/game/event.gd`, use typed on-ready references to those nodes. `_refresh()` must:

```gdscript
func _refresh() -> void:
    var data := event_instance.template if event_instance else null
    var is_resolved := event_instance != null and event_instance.is_resolved
    var style := StyleBoxFlat.new()
    style.bg_color = _get_type_color(data.event_type) if data else Color("4b5563")
    style.corner_radius_top_left = 8
    style.corner_radius_top_right = 8
    style.corner_radius_bottom_left = 8
    style.corner_radius_bottom_right = 8
    background.add_theme_stylebox_override("panel", style)
    icon.texture = data.icon if data else null
    icon.visible = icon.texture != null
    type_label.visible = not icon.visible
    type_label.text = _get_type_marker(data.event_type) if data else "?"
    name_label.text = _get_display_name(data)
    resolved_overlay.visible = is_resolved
    select_button.disabled = event_instance == null or is_resolved

func _on_select_button_pressed() -> void:
    if event_instance and not event_instance.is_resolved:
        event_selected.emit(event_instance)
```

Use `_get_type_color`, `_get_type_marker` and `_get_display_name` private helpers for the four `EventData.EventType` values. For monster content, `_get_display_name` returns `content.mob.mob_name` when present; otherwise it returns a title-cased `event_id` with underscores replaced by spaces.

- [ ] **Step 4: Run the focused and full tests to verify they pass**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/combat_model_test.gd --log-file "$env:TEMP\monocard-board-event-green.log"
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --quit-after 30 --log-file "$env:TEMP\monocard-main-scene.log"
```

Expected: both commands exit `0`; logs contain no `Parse Error:`, `SCRIPT ERROR:` or `Failed to load script`.

- [ ] **Step 5: Commit**

```powershell
git add -- scripts/game/event.gd scenes/game/event.tscn tests/combat_model_test.gd
git commit -m "feat: render interactive board events"
```
