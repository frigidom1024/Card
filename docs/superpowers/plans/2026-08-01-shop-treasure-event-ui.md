# Shop and Treasure Event UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic card-overlap event triggering plus playable Shop and Treasure event overlays using persistent gold and granting either cards or gold.

**Architecture:** `Board` emits an event signal only after a legal card is committed. `GameManager` is the application boundary: it locks drag interaction, routes supported event types to `EventOverlay`, uses a pure reward resolver for validation/state transitions, and creates `CardEntity` objects only for granted card rewards. Static resources hold templates and pools; `EventInstance` caches one encounter's dynamic state.

**Tech Stack:** Godot 4.7, GDScript, `.tscn` scenes, `.tres` Resources, headless `SceneTree` test scripts.

## Global Constraints

- Do not reset, restore, stage, or commit unrelated existing Combat v2 migration changes.
- `PlayerData.gold` is permanent currency and its initial value is exactly `30`.
- Treasure exposes two card options when at least two are configured, plus exactly one gold option; one successful claim resolves it.
- Gold options change `PlayerData.gold` and never create `CardInstance` or consume hand capacity.
- A failed card reward or purchase leaves gold, stock, treasure selection, and event resolution unchanged.
- Event footprints must have at least one fully empty board cell between them, so a 2×1 card cannot overlap two event zones.
- Only a newly, successfully placed card triggers an unresolved event. Preview, failed placement, and resolved events do not trigger.
- Test command: `godot --headless --path . --script <test-script>`. If `godot` is absent from `PATH`, use the local Godot 4.7 executable with identical arguments.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `scripts/player/player_data.gd` | Persistent gold. |
| `scripts/game/event/shop_item_data.gd` | Static serializable shop offer. |
| `scripts/game/event/treasure_reward_option.gd` | Cached card-or-gold treasure option. |
| `scripts/game/event/event_resolution_result.gd` | Typed resolver result. |
| `scripts/game/event/event_reward_resolver.gd` | Shop/treasure validation and runtime state transitions. |
| `scripts/game/event/event_zone.gd` | Per-instance sold flags and cached treasure options. |
| `scripts/game/event/event_shop_content.gd` | Inspector-configured shop offer list. |
| `scripts/game/event/event_treasure_content.gd` | Inspector-configured reward pool and gold range. |
| `scripts/game/board.gd` | Spacing, overlap lookup, and post-placement signal. |
| `scripts/game/event/event_placement_service.gd` | Spaced initial event placement. |
| `scripts/game/drag_layer.gd` | Overlay interaction lock. |
| `scripts/game/event.gd` | Non-clickable board event visual. |
| `scripts/game/event_overlay.gd` | Overlay lifecycle and request forwarding. |
| `scripts/game/event_shop.gd` | Shop rendering and feedback. |
| `scripts/game/event_treasure.gd` | Treasure rendering and feedback. |
| `scripts/game/event_reward_option_view.gd` | Reusable reward/offer widget. |
| `scripts/game_manager.gd` | Event routing and card entity grant boundary. |
| `scenes/game/event_overlay.tscn` | Fullscreen input-blocking overlay. |
| `scenes/game/event_shop.tscn` | Replaces current shop placeholder. |
| `scenes/game/event_treasure.tscn` | Treasure panel. |
| `scenes/game/event_reward_option_view.tscn` | Reward option widget scene. |
| `scenes/game/game_manager.tscn` | Instances overlay. |
| `data/event/content/*.tres` | Shop and treasure static configuration. |
| `data/event/events/shop_event.tres` | `forest_trader` SHOP template. |
| `data/event/events/treasure_event.tres` | `ancient_cache` TREASURE template. |
| `data/event/event_lib.tres` | Adds both templates to placement. |
| `data/player/player_data.tres` | Starts with 30 gold. |
| `tests/event_runtime_test.gd` | Resolver/cached-reward tests. |
| `tests/event_trigger_test.gd` | Board spacing and trigger tests. |

## Task 1: Add persistent currency and isolated event-runtime models

**Files:**
- Create: `scripts/game/event/shop_item_data.gd`
- Create: `scripts/game/event/treasure_reward_option.gd`
- Create: `scripts/game/event/event_resolution_result.gd`
- Create: `scripts/game/event/event_reward_resolver.gd`
- Modify: `scripts/player/player_data.gd:1-5`
- Modify: `scripts/game/event/event_zone.gd:1-27`
- Modify: `scripts/game/event/event_shop_content.gd:1-45`
- Modify: `scripts/game/event/event_treasure_content.gd:1-46`
- Delete: `scripts/game/event/shop_item.gd` and `scripts/game/event/shop_item.gd.uid`
- Test: `tests/event_runtime_test.gd`

**Interfaces:**
- Produces `EventRewardResolver.purchase_shop_item(instance, item_index, player, hand_has_capacity) -> EventResolutionResult`.
- Produces `EventRewardResolver.claim_treasure_reward(instance, option_index, player, hand_has_capacity, rng) -> EventResolutionResult`.
- Produces `EventRewardResolver.ensure_treasure_options(instance, rng) -> Array[TreasureRewardOption]`.

- [ ] **Step 1: Write failing resolver tests**

Create a `SceneTree` script using the `tests/combatv2_service_test.gd` `_expect`/`_finish_tests` pattern. Add these tests and fixtures:

```gdscript
func _test_shop_purchase_changes_only_successful_state() -> void:
    var player := PlayerDataScript.new()
    player.gold = 10
    var instance := _make_shop_instance([_offer("Twig Blade", 6)])
    var result := resolver.purchase_shop_item(instance, 0, player, true)
    _expect(result.success, "shop purchase succeeds")
    _expect(player.gold == 4, "deducts exact price")
    _expect(result.granted_card.card_name == "Twig Blade", "returns purchased card")
    _expect(instance.shop_sold_flags == [true], "marks item sold")
    _expect(not instance.is_resolved, "shop stays unresolved")

func _test_shop_failure_does_not_mutate_state() -> void:
    var player := PlayerDataScript.new()
    player.gold = 5
    var instance := _make_shop_instance([_offer("Twig Blade", 6)])
    var result := resolver.purchase_shop_item(instance, 0, player, true)
    _expect(not result.success, "insufficient gold rejects purchase")
    _expect(result.failure == EventResolutionResult.Failure.INSUFFICIENT_GOLD, "returns typed failure")
    _expect(player.gold == 5 and instance.shop_sold_flags == [false], "failure keeps all state")

func _test_treasure_options_are_cached_and_include_gold() -> void:
    var instance := _make_treasure_instance([_card("A"), _card("B"), _card("C")], Vector2i(9, 9))
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    var first := resolver.ensure_treasure_options(instance, rng)
    var second := resolver.ensure_treasure_options(instance, rng)
    _expect(first.size() == 3, "two cards plus gold")
    _expect(first[2].kind == TreasureRewardOption.Kind.GOLD and first[2].gold_amount == 9, "cached gold option")
    _expect(second == first, "same instance never rerolls")

func _test_full_hand_rejects_card_but_allows_gold() -> void:
    var player := PlayerDataScript.new()
    player.gold = 30
    var instance := _make_treasure_instance([_card("A"), _card("B")], Vector2i(7, 7))
    resolver.ensure_treasure_options(instance, RandomNumberGenerator.new())
    var card_result := resolver.claim_treasure_reward(instance, 0, player, false)
    var gold_result := resolver.claim_treasure_reward(instance, 2, player, false)
    _expect(not card_result.success and not instance.is_resolved, "full hand keeps treasure open")
    _expect(gold_result.success and player.gold == 37 and instance.is_resolved, "gold resolves treasure")
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
godot --headless --path . --script tests/event_runtime_test.gd
```

Expected: preload failure because the four new runtime classes do not exist.

- [ ] **Step 3: Implement the minimal runtime types and transitions**

Add these two concrete data types:

```gdscript
class_name ShopItemData
extends Resource

@export var card_data: CardData
@export_range(0, 999, 1) var price: int = 0

class_name TreasureRewardOption
extends RefCounted

enum Kind { CARD, GOLD }
var kind: Kind
var card_data: CardData
var gold_amount := 0

static func card(card: CardData) -> TreasureRewardOption:
    var option := TreasureRewardOption.new()
    option.kind = Kind.CARD
    option.card_data = card
    return option

static func gold(amount: int) -> TreasureRewardOption:
    var option := TreasureRewardOption.new()
    option.kind = Kind.GOLD
    option.gold_amount = amount
    return option
```

Use this exact result contract:

```gdscript
class_name EventResolutionResult
extends RefCounted

enum Failure { NONE, INVALID_EVENT, INVALID_INDEX, SOLD_OUT, INSUFFICIENT_GOLD, HAND_FULL, ALREADY_RESOLVED }
var success := false
var failure: Failure = Failure.NONE
var granted_card: CardData
var gold_delta := 0

static func rejected(reason: Failure) -> EventResolutionResult:
    var result := EventResolutionResult.new()
    result.failure = reason
    return result
```

Append `@export var gold: int = 30` to `PlayerData`. Add to `EventInstance`:

```gdscript
var shop_sold_flags: Array[bool] = []
var treasure_options: Array[TreasureRewardOption] = []
var selected_treasure_option := -1
```

Replace `EventShopContent.items` with `@export var items: Array[ShopItemData] = []`; remove content-resource purchase/sold state methods. Keep `EventTreasureContent.gold_range` and `card_rewards`, change the default `choices` to `2`, and add `draw_unique_choices(count, rng)` returning shuffled non-duplicate `CardData` values.

`ensure_treasure_options()` returns existing options when present; otherwise appends up to two unique card options and then exactly one gold option generated from the configured range. `purchase_shop_item()` initializes one false sold flag per static item, validates instance/content, index, resolved state, sold state, hand capacity, then gold, and only then deducts gold and marks sold. `claim_treasure_reward()` rejects resolved/invalid choices; rejects card choices with no hand capacity; for a gold choice adds gold, and for a card choice returns `granted_card`; it then records `selected_treasure_option` and calls `instance.resolve()`.

- [ ] **Step 4: Run the runtime test to verify it passes**

```powershell
godot --headless --path . --script tests/event_runtime_test.gd
```

Expected: exit code `0`; all four resolver scenarios pass.

- [ ] **Step 5: Commit the runtime model**

```powershell
git add scripts/player/player_data.gd scripts/game/event/shop_item_data.gd scripts/game/event/treasure_reward_option.gd scripts/game/event/event_resolution_result.gd scripts/game/event/event_reward_resolver.gd scripts/game/event/event_zone.gd scripts/game/event/event_shop_content.gd scripts/game/event/event_treasure_content.gd scripts/game/event/shop_item.gd scripts/game/event/shop_item.gd.uid tests/event_runtime_test.gd
git commit -m "feat: add event reward runtime state"
```

## Task 2: Enforce event spacing and emit triggers after legal placement

**Files:**
- Modify: `scripts/game/board.gd:1-425`
- Modify: `scripts/game/event/event_placement_service.gd:1-41`
- Modify: `scripts/game/drag_layer.gd:1-119`
- Modify: `scripts/game/event.gd:1-104`
- Create: `tests/event_trigger_test.gd`
- Modify: `tests/event_runtime_test.gd`

**Interfaces:**
- Produces `signal event_triggered(instance: EventInstance)`.
- Produces `Board.get_overlapping_unresolved_event(cells) -> EventInstance`.
- Produces `DragLayer.set_interaction_locked(locked: bool) -> void`.

- [ ] **Step 1: Write failing placement/trigger tests**

Create `tests/event_trigger_test.gd`, preload `board.tscn`, `event.tscn`, and the card entity scene. Add these exact scenarios:

```gdscript
func _test_event_placement_reserves_a_one_cell_gap() -> void:
    var board := _make_board(5, 1)
    _attach_event(board, "first", Vector2i(0, 0), Vector2i.ONE)
    var second := _new_event("second", Vector2i.ONE, Vector2i(1, 0))
    _expect(not board.can_attach_event(second), "one empty cell is required")

func _test_successful_card_placement_triggers_exactly_one_event() -> void:
    var board := _make_board(5, 2)
    _attach_event(board, "treasure", Vector2i(2, 0), Vector2i.ONE)
    var card := _make_card_at(board, Vector2(120, 40), 90.0)
    var triggered: Array[EventInstance] = []
    board.event_triggered.connect(func(instance): triggered.append(instance))
    _expect(board.add_card(card), "card is legally placed")
    _expect(triggered.size() == 1 and triggered[0].template.event_id == "treasure", "overlap emits matching event")

func _test_resolved_or_failed_placement_never_triggers() -> void:
    var board := _make_board(3, 2)
    var event_node := _attach_event(board, "resolved", Vector2i(1, 0), Vector2i.ONE)
    event_node.event_instance.resolve()
    var trigger_count := 0
    board.event_triggered.connect(func(_instance): trigger_count += 1)
    board.add_card(_make_card_at(board, Vector2(120, 40), 90.0))
    board.add_card(_make_card_at(board, Vector2(-80, 40), 90.0))
    _expect(trigger_count == 0, "resolved and rejected placements do not trigger")
```

Add a seeded `EventPlacementService` test in `event_runtime_test.gd` proving a later event cannot use a footprint or its mandatory empty boundary.

- [ ] **Step 2: Run tests and verify they fail**

```powershell
godot --headless --path . --script tests/event_trigger_test.gd
godot --headless --path . --script tests/event_runtime_test.gd
```

Expected: overlap fails because `Board.has_conflict()` currently forbids event cells, and gap validation fails because only direct event overlap is currently rejected.

- [ ] **Step 3: Implement event buffering, overlap detection, and lock**

Add to `Board`:

```gdscript
signal event_triggered(instance: EventInstance)

func get_event_buffer_cells(origin: Vector2i, event_size: Vector2i) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for x in range(origin.x - 1, origin.x + event_size.x + 1):
        for y in range(origin.y - 1, origin.y + event_size.y + 1):
            var cell := Vector2i(x, y)
            if _are_cells_in_bounds([cell]):
                result.append(cell)
    return result

func get_overlapping_unresolved_event(cells: Array[Vector2i]) -> EventInstance:
    var matches: Array[BoardEvent] = []
    for cell in cells:
        var event_node := _event_grid_owner.get(cell) as BoardEvent
        if event_node and event_node.event_instance and not event_node.event_instance.is_resolved and event_node not in matches:
            matches.append(event_node)
    if matches.size() > 1:
        push_error("Card placement overlaps multiple unresolved events")
        return null
    return matches[0].event_instance if matches.size() == 1 else null
```

`can_attach_event()` must retain actual-cell bounds/card checks, then reject candidates when any buffer cell is already an event cell. `has_conflict()` must no longer reject `_event_grid_owner`; event zones must be occupiable by cards. At the end of a successful `add_card()`, after cards and `_grid_owner` are updated, lookup the newly occupied cells and emit only the non-null unresolved match.

Add `interaction_locked := false` and `set_interaction_locked(locked)` to `DragLayer`; `on_card_drag_start()` and `on_card_drag_end()` return when locked. In `BoardEvent._refresh()`, always disable the select button and set the root `mouse_filter` to `Control.MOUSE_FILTER_IGNORE`; retain but do not connect `event_selected` for compatibility.

- [ ] **Step 4: Run focused regressions**

```powershell
godot --headless --path . --script tests/event_trigger_test.gd
godot --headless --path . --script tests/event_runtime_test.gd
godot --headless --path . --script tests/combat_model_test.gd
```

Expected: all exit `0`; existing board/event tests are updated only where their former adjacent-position expectations conflict with the new gap rule.

- [ ] **Step 5: Commit board-trigger behavior**

```powershell
git add scripts/game/board.gd scripts/game/event/event_placement_service.gd scripts/game/drag_layer.gd scripts/game/event.gd tests/event_trigger_test.gd tests/event_runtime_test.gd tests/combat_model_test.gd
git commit -m "feat: trigger events from card overlap"
```

## Task 3: Build reusable event-overlay and reward-option presentation

**Files:**
- Create: `scenes/game/event_overlay.tscn`
- Create: `scripts/game/event_overlay.gd`
- Create: `scenes/game/event_reward_option_view.tscn`
- Create: `scripts/game/event_reward_option_view.gd`
- Modify: `scenes/game/event_shop.tscn`
- Create: `scripts/game/event_shop.gd`
- Create: `scenes/game/event_treasure.tscn`
- Create: `scripts/game/event_treasure.gd`

**Interfaces:**
- Produces `EventOverlay.shop_purchase_requested(item_index: int)` and `EventOverlay.treasure_claim_requested(option_index: int)`.
- Produces `EventOverlay.open_event(instance, player_gold)`, `refresh_event(instance, player_gold, feedback)`, and `close_event()`.

- [ ] **Step 1: Define the visual acceptance contract in the overlay script**

Put these comments at the top of `scripts/game/event_overlay.gd` before scene construction:

```gdscript
# Visual acceptance:
# 1. The overlay covers the 1600×900 viewport with a dark input-blocking backdrop.
# 2. Board remains visible but no card can be dragged beneath the backdrop.
# 3. Shop shows current gold, three offers, price, Buy button, and Sold Out state.
# 4. Treasure shows two card choices and one clearly labeled gold choice.
# 5. Rejected actions leave the panel open and show a feedback message.
# 6. A treasure success closes the overlay; a shop success refreshes in place.
```

- [ ] **Step 2: Create the reusable reward/offer option**

Create `EventRewardOptionView` as a `PanelContainer` containing a `VBoxContainer` with unique-name `Title`, `Detail`, `PriceOrValue`, `ActionButton`, and `SoldOverlay` children. Its core script must expose:

```gdscript
class_name EventRewardOptionView
extends PanelContainer

signal pressed(option_index: int)

@onready var title: Label = %Title
@onready var detail: Label = %Detail
@onready var price_or_value: Label = %PriceOrValue
@onready var action_button: Button = %ActionButton
@onready var sold_overlay: Label = %SoldOverlay
var option_index := -1

func show_shop_offer(index: int, offer: ShopItemData, sold: bool) -> void:
    option_index = index
    title.text = offer.card_data.card_name
    detail.text = _card_detail(offer.card_data)
    price_or_value.text = "%d Gold" % offer.price
    action_button.text = "Sold Out" if sold else "Buy"
    action_button.disabled = sold
    sold_overlay.visible = sold

func show_treasure_option(index: int, option: TreasureRewardOption) -> void:
    option_index = index
    sold_overlay.visible = false
    if option.kind == TreasureRewardOption.Kind.GOLD:
        title.text = "Gold Cache"
        detail.text = "Add permanent currency"
        price_or_value.text = "+%d Gold" % option.gold_amount
    else:
        title.text = option.card_data.card_name
        detail.text = _card_detail(option.card_data)
        price_or_value.text = "Take Card"
    action_button.text = "Claim"
    action_button.disabled = false
```

Connect `ActionButton.pressed` to `pressed.emit(option_index)`. `_card_detail()` displays non-zero stats using `DMG +%d  DEF +%d  HEAL +%d`; when all are zero, it displays `card_data.description`.

- [ ] **Step 3: Create Shop, Treasure, and Overlay panels**

Replace `scenes/game/event_shop.tscn` with an `EventShopPanel` root panel containing unique-name `GoldLabel`, `Offers` (`HBoxContainer`), and `FeedbackLabel`. Its script receives `(instance, player_gold, feedback := "")`, clears old options, instantiates one `EventRewardOptionView` per `EventShopContent.items`, reads `instance.shop_sold_flags`, and emits `purchase_requested(index)`.

Create `event_treasure.tscn` with unique-name `Options` and `FeedbackLabel`; its script receives `(instance, feedback := "")`, clears old options, instantiates one view per `instance.treasure_options`, and emits `claim_requested(index)`.

Create `event_overlay.tscn` as a full-rect `Control`, `mouse_filter = STOP`, dark semi-transparent `ColorRect`, centered `MarginContainer`, and child Shop/Treasure panels. Use this API:

```gdscript
class_name EventOverlay
extends Control

signal shop_purchase_requested(item_index: int)
signal treasure_claim_requested(option_index: int)
signal closed
var active_instance: EventInstance

func open_event(instance: EventInstance, player_gold: int) -> void:
    active_instance = instance
    visible = true
    if instance.get_event_type() == EventData.EventType.SHOP:
        %ShopPanel.show_for(instance, player_gold)
    elif instance.get_event_type() == EventData.EventType.TREASURE:
        %TreasurePanel.show_for(instance)

func refresh_event(instance: EventInstance, player_gold: int, feedback: String) -> void:
    active_instance = instance
    if instance.get_event_type() == EventData.EventType.SHOP:
        %ShopPanel.show_for(instance, player_gold, feedback)
    else:
        %TreasurePanel.show_for(instance, feedback)

func close_event() -> void:
    active_instance = null
    visible = false
    closed.emit()
```

Keep it hidden by default. Treasure has no dismiss button; successful claim is its completion path. Do not add a shop refresh mechanic.

- [ ] **Step 4: Perform a scene smoke check**

```powershell
godot --editor --path .
```

Expected: all four new/changed scenes load without missing unique-name node errors; the overlay begins hidden and its backdrop fills the viewport.

- [ ] **Step 5: Commit the overlay UI**

```powershell
git add scenes/game/event_overlay.tscn scripts/game/event_overlay.gd scenes/game/event_reward_option_view.tscn scripts/game/event_reward_option_view.gd scenes/game/event_shop.tscn scripts/game/event_shop.gd scenes/game/event_treasure.tscn scripts/game/event_treasure.gd
git commit -m "feat: add shop and treasure event overlay UI"
```

## Task 4: Wire UI requests through GameManager and award real cards

**Files:**
- Modify: `scripts/game_manager.gd:1-49`
- Modify: `scenes/game/game_manager.tscn`
- Modify: `tests/event_runtime_test.gd`

**Interfaces:**
- Consumes `Board.event_triggered`, `EventOverlay` request signals, `EventRewardResolver`, `HandArea.is_full()`, `CardManager.create_card_entity()`, and `DragLayer.set_interaction_locked()`.
- Produces `GameManager.try_add_card_to_hand(card_data: CardData) -> bool` and the only public event-reward application boundary.

- [ ] **Step 1: Add a result-shape regression test**

Append to `event_runtime_test.gd`:

```gdscript
func _test_card_and_gold_results_have_non_overlapping_payloads() -> void:
    var player := PlayerDataScript.new()
    player.gold = 20
    var shop := _make_shop_instance([_offer("Twig Blade", 3)])
    var treasure := _make_treasure_instance([_card("A"), _card("B")], Vector2i(5, 5))
    resolver.ensure_treasure_options(treasure, RandomNumberGenerator.new())
    var purchase := resolver.purchase_shop_item(shop, 0, player, true)
    var gold_claim := resolver.claim_treasure_reward(treasure, 2, player, true)
    _expect(purchase.success and purchase.granted_card != null and purchase.gold_delta == 0, "card payload is hand-only")
    _expect(gold_claim.success and gold_claim.granted_card == null and gold_claim.gold_delta == 5, "gold payload is currency-only")
```

- [ ] **Step 2: Run the test before integration**

```powershell
godot --headless --path . --script tests/event_runtime_test.gd
```

Expected: exit code `0`; this guards the GameManager against creating a card for gold rewards.

- [ ] **Step 3: Implement GameManager routing and preflight**

Add `var reward_resolver := EventRewardResolver.new()` and `@onready var event_overlay: EventOverlay = $EventOverlay`. In `_ready()`, connect board/overlay signals. Add this card-creation boundary:

```gdscript
func try_add_card_to_hand(card_data: CardData) -> bool:
    if card_data == null or hand_area.is_full():
        return false
    var instance := CardInstance.new(card_data)
    var entity := card_manager.create_card_entity(instance)
    if entity == null:
        return false
    entity.drag_layer = drag_layer
    if not hand_area.add_card(entity):
        entity.queue_free()
        return false
    cards_inst.append(instance)
    card_entities.append(entity)
    return true
```

`_on_board_event_triggered(instance)` ignores null/resolved instances and ignores events while the overlay is visible. It locks dragging and opens the overlay for SHOP; it first calls `ensure_treasure_options(instance)` then locks/opens for TREASURE; it only emits a warning for MONSTER/BOSS. Before resolver card calls, pass `not hand_area.is_full()` and verify `card_manager.card_scene != null`. On preflight failure refresh feedback `Hand is full` or `Card reward is unavailable` without calling the resolver. On a successful card result call `try_add_card_to_hand`; on a gold result never call it. A successful treasure call closes the overlay; a successful shop call refreshes it. Map resolver failures to exactly `Not enough gold`, `Hand is full`, `Sold out`, `Reward already claimed`, or `This option is unavailable`. On `EventOverlay.closed`, call `drag_layer.set_interaction_locked(false)`.

Add the overlay scene as the final child in `game_manager.tscn`, above board, hand, card manager, and drag layer.

- [ ] **Step 4: Run integration regressions**

```powershell
godot --headless --path . --script tests/event_runtime_test.gd
godot --headless --path . --script tests/combat_model_test.gd
godot --headless --path . --script tests/combatv2_card_rule_test.gd
godot --headless --path . --script tests/combatv2_service_test.gd
```

Expected: all exit `0`.

- [ ] **Step 5: Commit the integration**

```powershell
git add scripts/game_manager.gd scenes/game/game_manager.tscn tests/event_runtime_test.gd
git commit -m "feat: resolve shop and treasure event rewards"
```

## Task 5: Configure playable Shop and Treasure map content

**Files:**
- Modify: `data/player/player_data.tres`
- Modify: `data/event/content/event_shop_content.tres`
- Modify: `data/event/content/event_treasure_content.tres`
- Create: `data/event/events/shop_event.tres`
- Create: `data/event/events/treasure_event.tres`
- Modify: `data/event/event_lib.tres`
- Modify: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes `ShopItemData`, `EventShopContent`, `EventTreasureContent`, and `EventData.EventType`.
- Produces `forest_trader` SHOP and `ancient_cache` TREASURE templates for `GameManager.init_events()`.

- [ ] **Step 1: Add failing resource-validation assertions**

After existing event-library checks in `tests/combat_model_test.gd`, add:

```gdscript
var shop_content := load("res://data/event/content/event_shop_content.tres") as EventShopContent
_expect(shop_content != null and shop_content.items.size() == 3, "shop has three offers")
if shop_content and shop_content.items.size() == 3:
    _expect(shop_content.items[0].price == 6, "first shop price is six")

var treasure_content := load("res://data/event/content/event_treasure_content.tres") as EventTreasureContent
_expect(treasure_content != null, "treasure content loads")
if treasure_content:
    _expect(treasure_content.choices == 2, "treasure has two card choices")
    _expect(treasure_content.card_rewards.size() >= 2, "treasure pool supports two choices")
    _expect(treasure_content.gold_range == Vector2i(20, 50), "treasure gold range matches design")

var configured_player := load("res://data/player/player_data.tres") as PlayerData
_expect(configured_player != null and configured_player.gold == 30, "player starts with thirty gold")
```

Also assert `EventLib.entries` contains a `SHOP` template ID `forest_trader` and a `TREASURE` template ID `ancient_cache`.

- [ ] **Step 2: Run resource validation to verify it fails**

```powershell
godot --headless --path . --script tests/combat_model_test.gd
```

Expected: the test fails because current shop items are empty, treasure pool is empty, player data has no gold field, and the library has only monster entries.

- [ ] **Step 3: Create exact event-resource configuration**

Set `gold = 30` in `data/player/player_data.tres`.

Create three `ShopItemData` subresources in `event_shop_content.tres`:

```text
res://data/cards/VineShortblade.tres       price 6
res://data/cards/ThornBarrier.tres         price 8
res://data/cards/ClearSpringWoodVial.tres  price 10
```

Set `max_items = 3`. Configure `event_treasure_content.tres` with `VineShortblade.tres`, `ThornHeavyBlade.tres`, and `ClearSpringWoodVial.tres`; set `gold_range = Vector2i(20, 50)` and `choices = 2`.

Create the following templates:

```text
shop_event.tres: event_id "forest_trader", event_type SHOP, size Vector2i.ONE, content event_shop_content.tres
treasure_event.tres: event_id "ancient_cache", event_type TREASURE, size Vector2i.ONE, content event_treasure_content.tres
```

Add both as `EventEntry` subresources in `event_lib.tres` with `min_count = 1` and `max_count = 1`; leave all monster entries unchanged.

- [ ] **Step 4: Run resource and event tests**

```powershell
godot --headless --path . --script tests/combat_model_test.gd
godot --headless --path . --script tests/event_runtime_test.gd
godot --headless --path . --script tests/event_trigger_test.gd
```

Expected: all exit `0`; initial placement uses the one-cell event spacing rule and places every entry that fits.

- [ ] **Step 5: Commit configured content**

```powershell
git add data/player/player_data.tres data/event/content/event_shop_content.tres data/event/content/event_treasure_content.tres data/event/events/shop_event.tres data/event/events/treasure_event.tres data/event/event_lib.tres tests/combat_model_test.gd
git commit -m "feat: configure shop and treasure events"
```

## Task 6: Execute full regression and manual UI acceptance

**Files:**
- Modify only source files from Tasks 1-5 when a test or manual verification demonstrates a concrete defect.
- Test: `tests/combat_model_test.gd`, `tests/event_runtime_test.gd`, `tests/event_trigger_test.gd`, `tests/combatv2_card_rule_test.gd`, `tests/combatv2_service_test.gd`

**Interfaces:**
- Consumes all outputs from Tasks 1-5.
- Produces a verified Shop/Treasure flow without Combat v2 regressions.

- [ ] **Step 1: Run the full headless suite**

```powershell
godot --headless --path . --script tests/combat_model_test.gd
godot --headless --path . --script tests/event_runtime_test.gd
godot --headless --path . --script tests/event_trigger_test.gd
godot --headless --path . --script tests/combatv2_card_rule_test.gd
godot --headless --path . --script tests/combatv2_service_test.gd
```

Expected: each process exits `0`.

- [ ] **Step 2: Verify the Shop path in the playable scene**

```powershell
godot --editor --path .
```

Start the game. Build the chain until it overlaps `forest_trader`. Verify the overlay blocks dragging, starts at 30 gold, and shows three offers. Buy `Vine Shortblade` once: gold becomes 24, exactly one hand card is added, and that offer reads `Sold Out`. Click it again and verify no state changes. Set player gold below 6 through the Inspector, select another available offer, and verify feedback reads `Not enough gold` while its stock remains available.

- [ ] **Step 3: Verify Treasure and full-hand behavior**

Restart the scene. Reach `ancient_cache`; verify two card options plus `Gold Cache`. Keep the event open and refresh its visual binding; verify names and gold amount remain identical. Fill the hand to `max_hand_size`, select a card option, and verify `Hand is full` while the overlay remains open. Select `Gold Cache`; verify gold rises by the displayed amount, no card is added, the overlay closes, and re-overlap cannot re-open the resolved event.

- [ ] **Step 4: Verify spacing and unsupported event routing**

Inspect a generated board: every pair of event footprints has at least one empty grid cell between them. Place a horizontal 2×1 card across an event boundary; only one overlay may open. Reach a Monster event and confirm it does not open Shop/Treasure UI; an output warning is acceptable until the combat UI is attached.

- [ ] **Step 5: Commit only real verification fixes**

Run `git status --short` after Steps 1-4. If a defect required a source change, return to the task that owns that file, repeat its focused test and its explicit Step 5 commit command. If no files changed, create no empty commit.

## Plan Self-Review

### Spec coverage

- Card-overlap-only triggering: Task 2.
- One-cell gap between complete event footprints: Task 2 and Task 6 Step 4.
- Full-screen dark, input-blocking overlay: Task 3 and Task 6 Step 2.
- Permanent starting 30 gold: Tasks 1 and 5.
- Shop purchase, sold state, insufficient gold, and full-hand paths: Tasks 1, 3, 4, and 6.
- Two cached card options plus one gold option: Tasks 1, 3, 5, and 6.
- Gold never becomes a hand card: Tasks 1, 4, and 6.
- Treasure resolves once after successful claim: Tasks 1, 4, and 6.
- Existing Combat v2 work is untouched and regression-tested: Task 4 Step 4 and Task 6 Step 1.

### Type consistency

- `Board.event_triggered` carries `EventInstance`; `GameManager._on_board_event_triggered` consumes it.
- `EventOverlay` emits indices only; `GameManager` retains ownership of the active instance and resolver call.
- `EventRewardResolver` returns `EventResolutionResult`; only `GameManager.try_add_card_to_hand` creates `CardInstance` and `CardEntity`.
- `EventInstance.shop_sold_flags` and `EventInstance.treasure_options` are the only per-event dynamic reward state.
