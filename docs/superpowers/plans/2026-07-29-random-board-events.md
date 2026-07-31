# Random Board Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate initial events from `EventLib`, randomly place them on valid board cells, attach their `BoardEvent` nodes to the board, and prevent card/event overlap.

**Architecture:** `EventPlacementService` owns event-generation and random-placement policy. `Board` owns grid bounds, event occupancy, card/event collision checks, and the attached event-node collection. `GameManager` only supplies `EventLib` and calls the service during startup.

**Tech Stack:** Godot 4.7, GDScript, `Resource`-backed event data, `Control`-based `BoardEvent`, headless Godot regression script.

## Global Constraints

- Preserve existing user changes outside the files explicitly staged by each task; never reset unrelated data, scenes, logs, or temporary files.
- Keep `EventData.size` as the only source of event footprint dimensions.
- Do not add external dependencies.
- Events must be fully in bounds, must not overlap other events or cards, and must be skipped safely when no placement exists.
- Runtime randomness must use `RandomNumberGenerator.randomize()`; regression tests must inject a seeded generator.
- Validate with `D:\InstallPath\godot\Godot_v4.7-stable_win64.exe --headless --path . --script res://tests/combat_model_test.gd` after every green step.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `scripts/game/board.gd` | Event-cell calculation, occupancy validation, board attachment/removal, and card/event collision integration. |
| `scripts/game/event/event_placement_service.gd` | Generates instances from `EventLib`, picks a random valid origin, and requests board attachment. |
| `scripts/game/event/event_lib.gd` | Typed factory for a configured `BoardEvent` node. |
| `scripts/game/event.gd` | Builds its editor-preview instance using the current no-argument `EventData.create_instance()` contract. |
| `scripts/game_manager.gd` | Exports `EventLib` and invokes initial placement once. |
| `scenes/game/game_manager.tscn` | Assigns `data/event/event_lib.tres` to `GameManager.event_lib`. |
| `tests/combat_model_test.gd` | Real-scene regression coverage for board event lifecycle, random placement, capacity handling, and startup integration. |

---

### Task 1: Give `Board` Focused Event Occupancy and Attachment APIs

**Files:**
- Modify: `scripts/game/board.gd:15-20, 205-360`
- Modify: `tests/combat_model_test.gd:1-12, after _test_board_event_binding()`

**Interfaces:**
- Consumes: a configured `BoardEvent` whose `event_instance.origin` has already been assigned.
- Produces:
  - `func get_event_cells(origin: Vector2i, event_size: Vector2i) -> Array[Vector2i]`
  - `func can_attach_event(instance: EventInstance) -> bool`
  - `func attach_event(event_node: BoardEvent) -> bool`
  - `func remove_event(event_node: BoardEvent) -> bool`
  - `var events: Array[BoardEvent]`

- [ ] **Step 1: Write the failing board-lifecycle test**

Add scene preloads and the following test to `tests/combat_model_test.gd`:

```gdscript
const BoardScene = preload("res://scenes/game/board.tscn")

func _test_board_event_lifecycle() -> void:
	var board := BoardScene.instantiate() as Board
	board.width = 3
	board.height = 2
	board.cell_size = 80
	root.add_child(board)

	var template := EventData.new()
	template.event_id = "wide_event"
	template.size = Vector2i(2, 1)
	var instance := template.create_instance()
	instance.origin = Vector2i(1, 1)
	var event_node := BoardEventScene.instantiate() as BoardEvent
	event_node.setup(instance, board.cell_size)

	_expect(board.get_event_cells(instance.origin, instance.get_size()) == [Vector2i(1, 1), Vector2i(2, 1)], "board calculates every cell occupied by a wide event")
	_expect(board.can_attach_event(instance), "in-bounds event can be attached to an empty board")
	_expect(board.attach_event(event_node), "board attaches a valid event node")
	_expect(event_node.get_parent() == board and board.events.size() == 1, "board owns the attached event node")
	_expect(board.has_conflict([Vector2i(1, 1)]), "event-occupied cells conflict with card placement")
	_expect(not board.can_attach_event(instance), "board rejects a second event on occupied cells")
	_expect(board.remove_event(event_node), "board removes an attached event")
	_expect(board.events.is_empty() and not board.has_conflict([Vector2i(1, 1)]), "removing an event releases its occupied cells")
	board.queue_free()
```

Call `_test_board_event_lifecycle()` from `_run_deferred_tests()` before `_finish_tests()`.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/combat_model_test.gd
```

Expected: the output reports missing `Board.get_event_cells`, `Board.can_attach_event`, `Board.attach_event`, and `Board.remove_event` methods.

- [ ] **Step 3: Implement the minimal board APIs**

In `scripts/game/board.gd`, add a separate event occupancy map next to `_grid_owner`:

```gdscript
var events: Array[BoardEvent] = []
var _event_grid_owner: Dictionary[Vector2i, BoardEvent] = {}
```

Add these helpers before the card-placement section:

```gdscript
func get_event_cells(origin: Vector2i, event_size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in event_size.x:
		for y in event_size.y:
			cells.append(origin + Vector2i(x, y))
	return cells


func _are_cells_in_bounds(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if cell.x < 0 or cell.x >= width or cell.y < 0 or cell.y >= height:
			return false
	return true


func can_attach_event(instance: EventInstance) -> bool:
	if instance == null or instance.template == null:
		return false
	var cells := get_event_cells(instance.origin, instance.get_size())
	if cells.is_empty() or not _are_cells_in_bounds(cells):
		return false
	for cell in cells:
		if _grid_owner.has(cell) or _event_grid_owner.has(cell):
			return false
	return true


func attach_event(event_node: BoardEvent) -> bool:
	if event_node == null or not can_attach_event(event_node.event_instance):
		return false
	var cells := get_event_cells(event_node.event_instance.origin, event_node.event_instance.get_size())
	for cell in cells:
		_event_grid_owner[cell] = event_node
	events.append(event_node)
	add_child(event_node)
	return true


func remove_event(event_node: BoardEvent) -> bool:
	if event_node == null or event_node not in events:
		return false
	var cells := get_event_cells(event_node.event_instance.origin, event_node.event_instance.get_size())
	for cell in cells:
		if _event_grid_owner.get(cell) == event_node:
			_event_grid_owner.erase(cell)
	events.erase(event_node)
	event_node.queue_free()
	return true
```

Update `has_conflict()` so it returns `true` when either `_grid_owner` or `_event_grid_owner` contains a checked cell. Reuse `_are_cells_in_bounds()` in `preview_card()` and `can_place_card()` only where it preserves existing behavior.

- [ ] **Step 4: Run the regression test to verify it passes**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/combat_model_test.gd
```

Expected: no `ERROR:`, `SCRIPT ERROR:`, or `Parse Error:` lines.

- [ ] **Step 5: Commit the board lifecycle change**

```powershell
git add -- scripts/game/board.gd tests/combat_model_test.gd
git commit -m "feat: add board event occupancy"
```

---

### Task 2: Add Random Event Placement Service and Typed Event Factory

**Files:**
- Create: `scripts/game/event/event_placement_service.gd`
- Modify: `scripts/game/event/event_lib.gd:5-20`
- Modify: `tests/combat_model_test.gd:1-12, after _test_board_event_lifecycle()`

**Interfaces:**
- Consumes: `EventLib.generate_event_datas()`, `EventLib.create_event_scene(instance, cell_size)`, and `Board.can_attach_event(instance)`.
- Produces:
  - `class_name EventPlacementService`
  - `func place_initial_events(event_lib: EventLib, board: Board, rng: RandomNumberGenerator = null) -> Array[EventInstance]`
  - `func EventLib.create_event_scene(event_inst: EventInstance, cell_size: int) -> BoardEvent`

- [ ] **Step 1: Write failing random-placement and capacity tests**

Add the following test and helper to `tests/combat_model_test.gd`:

```gdscript
func _make_event_entry(event_id: String, event_size: Vector2i) -> EventEntry:
	var data := EventData.new()
	data.event_id = event_id
	data.size = event_size
	var entry := EventEntry.new()
	entry.event_data = data
	entry.min_count = 1
	entry.max_count = 1
	return entry


func _test_random_event_placement() -> void:
	var board := BoardScene.instantiate() as Board
	board.width = 4
	board.height = 3
	board.cell_size = 80
	root.add_child(board)
	var event_lib := EventLib.new()
	event_lib.event_scene = BoardEventScene
	event_lib.entries = [_make_event_entry("wide", Vector2i(2, 1)), _make_event_entry("tall", Vector2i(1, 2)), _make_event_entry("small", Vector2i.ONE)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260729
	var service := EventPlacementService.new()
	var placed := service.place_initial_events(event_lib, board, rng)

	_expect(placed.size() == 3 and board.events.size() == 3, "placement service attaches every event that fits")
	var occupied: Dictionary[Vector2i, bool] = {}
	for event_node in board.events:
		_expect(event_node.get_parent() == board, "placement service renders events under the board")
		for cell in board.get_event_cells(event_node.event_instance.origin, event_node.event_instance.get_size()):
			_expect(cell.x >= 0 and cell.x < board.width and cell.y >= 0 and cell.y < board.height, "placed event cells stay in bounds")
			_expect(not occupied.has(cell), "randomly placed events do not overlap")
			occupied[cell] = true
	board.queue_free()

	var cramped_board := BoardScene.instantiate() as Board
	cramped_board.width = 1
	cramped_board.height = 1
	root.add_child(cramped_board)
	var cramped_lib := EventLib.new()
	cramped_lib.event_scene = BoardEventScene
	cramped_lib.entries = [_make_event_entry("first", Vector2i.ONE), _make_event_entry("second", Vector2i.ONE)]
	var cramped_rng := RandomNumberGenerator.new()
	cramped_rng.seed = 7
	var cramped_placed := service.place_initial_events(cramped_lib, cramped_board, cramped_rng)
	_expect(cramped_placed.size() == 1 and cramped_board.events.size() == 1, "placement service skips events when the board has no valid space")
	cramped_board.queue_free()
```

Call `_test_random_event_placement()` from `_run_deferred_tests()` after the board-lifecycle test.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/combat_model_test.gd
```

Expected: `Could not resolve class "EventPlacementService"` or a missing `place_initial_events` method error.

- [ ] **Step 3: Implement the service and factory**

Create `scripts/game/event/event_placement_service.gd`:

```gdscript
class_name EventPlacementService
extends RefCounted

func place_initial_events(
	event_lib: EventLib,
	board: Board,
	rng: RandomNumberGenerator = null
) -> Array[EventInstance]:
	var placed: Array[EventInstance] = []
	if event_lib == null or board == null:
		return placed
	var random := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		random.randomize()
	for instance in event_lib.generate_event_datas():
		var candidates := _get_valid_origins(instance, board)
		if candidates.is_empty():
			push_warning("No board space remains for event: %s" % instance.template.event_id)
			continue
		instance.origin = candidates[random.randi_range(0, candidates.size() - 1)]
		var event_node := event_lib.create_event_scene(instance, board.cell_size)
		if event_node and board.attach_event(event_node):
			placed.append(instance)
	return placed


func _get_valid_origins(instance: EventInstance, board: Board) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	if instance == null or instance.template == null:
		return candidates
	var event_size := instance.get_size()
	for x in maxi(0, board.width - event_size.x + 1):
		for y in maxi(0, board.height - event_size.y + 1):
			var origin := Vector2i(x, y)
			instance.origin = origin
			if board.can_attach_event(instance):
				candidates.append(origin)
	instance.origin = Vector2i(-1, -1)
	return candidates
```

Update `scripts/game/event/event_lib.gd` so the factory is typed and safely handles an unconfigured scene:

```gdscript
func create_event_scene(event_inst: EventInstance, cell_size: int) -> BoardEvent:
	if event_scene == null or event_inst == null:
		return null
	var board_event := event_scene.instantiate() as BoardEvent
	if board_event == null:
		return null
	board_event.setup(event_inst, cell_size)
	return board_event
```

- [ ] **Step 4: Run the regression test to verify it passes**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/combat_model_test.gd
```

Expected: the seeded test places three events without shared cells; the one-cell board contains exactly one event and reports no engine errors.

- [ ] **Step 5: Commit the random placement service**

```powershell
git add -- scripts/game/event/event_placement_service.gd scripts/game/event/event_lib.gd tests/combat_model_test.gd
git commit -m "feat: place random board events"
```

---

### Task 3: Wire Initial Event Placement into Game Startup

**Files:**
- Modify: `scripts/game_manager.gd:1-45`
- Modify: `scenes/game/game_manager.tscn:1-30`
- Modify: `scripts/game/event.gd:31-36`
- Modify: `tests/combat_model_test.gd:1-12, after _test_random_event_placement()`

**Interfaces:**
- Consumes: `EventPlacementService.place_initial_events(event_lib, board)`.
- Produces:
  - `@export var event_lib: EventLib` on `GameManager`.
  - `func init_events() -> void` that performs exactly one startup placement call.

- [ ] **Step 1: Write the failing game-startup integration test**

Add this preload and test to `tests/combat_model_test.gd`:

```gdscript
const GameManagerScene = preload("res://scenes/game/game_manager.tscn")

func _test_game_manager_initial_events() -> void:
	var game_manager := GameManagerScene.instantiate()
	root.add_child(game_manager)
	_expect(game_manager.event_lib != null, "game manager scene supplies an event library")
	_expect(not game_manager.board.events.is_empty(), "game manager creates initial board events during startup")
	for event_node in game_manager.board.events:
		_expect(event_node.event_instance != null and event_node.get_parent() == game_manager.board, "initial events keep their runtime instance and board parent")
	game_manager.queue_free()
```

Call `_test_game_manager_initial_events()` from `_run_deferred_tests()` after the random-placement test.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/combat_model_test.gd
```

Expected: an invalid `event_lib` property or an assertion that the board has no initial events.

- [ ] **Step 3: Implement startup wiring and preview compatibility**

In `scripts/game_manager.gd`, add the exported library and service field near `player_data`:

```gdscript
@export var event_lib: EventLib
var _event_placement_service := EventPlacementService.new()
```

Call `init_events()` after `init_player_cards()` in `_ready()`, then implement:

```gdscript
func init_events() -> void:
	if event_lib == null:
		push_warning("GameManager is missing EventLib")
		return
	_event_placement_service.place_initial_events(event_lib, board)
```

In `scenes/game/game_manager.tscn`, add an external `EventLib` resource reference and assign it to the root node:

```text
[ext_resource type="Resource" path="res://data/event/event_lib.tres" id="9_event_lib"]

[node name="GameManager" type="Node"]
event_lib = ExtResource("9_event_lib")
```

Use the scene's existing root-node syntax and generated resource UID formatting when saving through Godot.

Update `scripts/game/event.gd` so the preview obeys the current `EventData.create_instance()` signature:

```gdscript
func _ready() -> void:
	if event_instance == null and preview_event:
		var preview_instance := preview_event.create_instance()
		preview_instance.origin = preview_origin
		setup(preview_instance, preview_cell_size)
	else:
		_refresh()
```

- [ ] **Step 4: Run full startup verification**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe'
& $godot --headless --path . --script res://tests/combat_model_test.gd
& $godot --headless --path . res://scenes/game/game_manager.tscn --quit-after 2
& $godot --headless --path . --quit-after 10
git diff --check -- scripts/game_manager.gd scenes/game/game_manager.tscn scripts/game/event.gd tests/combat_model_test.gd
```

Expected: every command exits with code `0` and no output contains `ERROR:`, `SCRIPT ERROR:`, `Parse Error:`, or `Failed to load script`.

- [ ] **Step 5: Commit the startup integration**

```powershell
git add -- scripts/game_manager.gd scenes/game/game_manager.tscn scripts/game/event.gd tests/combat_model_test.gd
git commit -m "feat: spawn initial board events"
```

---

### Task 4: Verify the Complete Event Placement Flow

**Files:**
- Verify: `scripts/game/board.gd`
- Verify: `scripts/game/event/event_placement_service.gd`
- Verify: `scripts/game/event/event_lib.gd`
- Verify: `scripts/game/event.gd`
- Verify: `scripts/game_manager.gd`
- Verify: `scenes/game/game_manager.tscn`
- Verify: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes: all completed public APIs from Tasks 1-3.
- Produces: fresh evidence that the runtime can generate, place, attach, and render initial events without engine errors.

- [ ] **Step 1: Inspect staged scope before final verification**

Run:

```powershell
git diff --name-only
git diff --check -- scripts/game/board.gd scripts/game/event/event_placement_service.gd scripts/game/event/event_lib.gd scripts/game/event.gd scripts/game_manager.gd scenes/game/game_manager.tscn tests/combat_model_test.gd
```

Expected: only intentional task files are included in any future staging command; no whitespace errors are reported.

- [ ] **Step 2: Run the formal regression and smoke checks**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe'
& $godot --headless --path . --script res://tests/combat_model_test.gd
& $godot --headless --path . res://scenes/game/game_manager.tscn --quit-after 2
& $godot --headless --path . --quit-after 10
```

Expected: all three commands exit with code `0`; their combined output contains no `ERROR:`, `SCRIPT ERROR:`, `Parse Error:`, or `Failed to load script` lines.

- [ ] **Step 3: Check the intended runtime outcomes against the design**

Confirm from the regression tests and node state:

```text
- Every placed EventInstance has a non-negative origin.
- Every placed BoardEvent is parented by Board.
- No event cell is outside the board rectangle.
- No two events share a cell.
- Board.has_conflict() rejects event-occupied cells for cards.
- A full board skips remaining events without changing existing event ownership.
- GameManager starts with a configured EventLib and a non-empty board.events list.
```

- [ ] **Step 4: Commit any final verification-only test adjustments**

If and only if Task 4 required a test-only adjustment, stage only that test file and commit it:

```powershell
git add -- tests/combat_model_test.gd
git commit -m "test: cover board event placement"
```

If no adjustment was required, do not create an empty commit.
