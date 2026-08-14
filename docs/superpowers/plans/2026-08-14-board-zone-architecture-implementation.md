# Board Zone Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the active legacy CardEntity board flow with a Card/CardInstance-based Board composed from independently testable BoardZone and BoardEventZone components.

**Architecture:** BoardZone owns card-grid and drag-space transactions, BoardEventZone owns event-grid transactions, and Board converts their structured results into existing business signals. GameManager composes one DraggerLayer with persistent Hand, Board, Shop, and Reclaim zones and owns the single synchronous return-to-hand handler.

**Tech Stack:** Godot 4.7, GDScript, SceneTree headless tests

**Spec:** `docs/superpowers/specs/2026-08-13-board-zone-architecture-design.md`

## Global Constraints

- `CardInstance` is the only source of truth for `cur_zone`, `battlefield_pos`, and `direction`; production code in the new flow must not read or write `Card.cur_zone`.
- Every visible `Card` keeps the exact `CardInstance` passed to `bind_card_inst()`; never duplicate or replace the instance during Hand, Board, Shop, GUIDE, or Reclaim transfers.
- `bind_card_inst()` and every mutation that changes visible card data must be followed by `Card.refresh_display()` so points, armor, and artwork stay synchronized.
- Drag commits remain synchronous and atomic after validation: call `target.drag_end_target(card, true)` before `source.drag_end_source(card, true)`.
- Do not add `finalize_drag_target()`, deferred commits, rollback callbacks, or a third drag protocol phase.
- `DraggerLayer` resolves the source only from registered zones through `owns_card(card)` and caches that source for the entire drag.
- `BoardZone` must not depend on, search for, or call `HandZone`.
- `Board` must not register with `DraggerLayer` and must not proxy card-grid or event-grid spatial APIs.
- Preserve the existing Board business signal names, except remove the duplicate `card_placed` signal.
- GUIDE placement must emit `placement_committed(GUIDE_RESOLVED)` before `card_return_requested(guide)`, must not create a chain-retraction transaction, and must never become a stable BoardZone member.
- A card directly dragged by the player is received by the target zone; Board requests return only for GUIDE and detached follower cards.
- Shop pricing, refresh, purchase, registration, and restock rules stay unchanged; Reclaim gold rules stay unchanged.
- The active game page contains exactly one `DraggerLayer`; HandZone, BoardZone, ShopZone, and ReclaimZone all register with it and every visible Card binds to it.
- `Board.card_return_requested` has exactly one active page-level handler, and that handler calls `HandZone.add_card(card, true)` synchronously.
- Every new or materially refactored component script and scene root must include a Chinese Godot documentation block that states its responsibility, explicitly lists what it manages, what it does not manage, how callers use it, and its direct dependencies.
- Component comments must describe the actual final API and ownership boundary; do not copy a legacy component's responsibilities into the new component documentation.

---

## Component Documentation Standard

Every component introduced or substantially refactored by this plan must begin with a documentation block in the component's primary script. Use this structure, adapting the content to the actual component:

```gdscript
## 卡牌区域组件
##
## 负责管理卡牌在本区域中的稳定成员关系与拖拽事务。
## 包括：
## - 区域成员登记与所有权查询
## - 拖拽开始、取消和提交
## - CardInstance 的区域状态同步
##
## 不负责：
## - 其他区域的成员管理
## - 手牌回收或金币结算
## - 跨系统业务流程协调
##
## 使用方式：
## 先注入 DraggerLayer，再通过 add_card() 或拖拽协议接收 Card。
##
## 依赖：
## Card：提供卡牌视图与拖拽交互。
## CardInstance：保存卡牌的唯一业务状态。
## DraggerLayer：协调区域间的同步拖拽提交。
```

The implementation must provide equivalent documentation for these components:

- `Card` and `CardInstance`;
- `CardZone`, `HandZone`, `ShopZone`, and `ReclaimZone`;
- `DraggerLayer`;
- `BoardZone` and `BoardEventZone`;
- `Board`;
- `RunCardService` and the active `GameManager` page composition.

For scene-only composition files, document the root component in the attached script and add a concise scene comment or node metadata when the scene has a non-obvious child wiring requirement. Each task's implementation step must update comments at the same time as code, and its commit step must include a documentation review.

---

## File Responsibility Map

### Card state and drag protocol

- `scripts/card/card_instance.gd`: persistent card gameplay state and zone enum.
- `scenes/card/card.gd`: CardInstance binding, drag interaction, and visual refresh only.
- `scripts/zone/card_zone.gd`: shared zone protocol, including stable ownership query.
- `scripts/zone/handzone.gd`: stable hand membership, layout, source snapshot, and unified return entry point.
- `scripts/game/drag_layer/dragger_layer.gd`: registered-zone source resolution and target-first synchronous commit.
- `scripts/zone/shop_zone.gd`: stable product slots and purchase source transaction.
- `scripts/zone/reclaim_zone.gd`: stateless Hand-only reclaim target.

### Board decomposition

- `scripts/game/board_card_placement.gd`: BoardZone placement operation DTO.
- `scripts/game/board_card_retraction.gd`: BoardZone chain-detach operation DTO.
- `scripts/zone/board_zone.gd`: card-grid ownership, previews, placement, GUIDE shift, and chain detach.
- `scripts/zone/board_event_zone.gd`: event-grid ownership, bounds, buffering, placement, movement, and removal.
- `scripts/game/board.gd`: translates BoardZone operations into existing business DTOs and signals.
- `scripts/game/board_placement_result.gd`: Card-based public placement result.
- `scripts/game/chain_retraction_transaction.gd`: Card-based public retraction result.
- `scenes/game/board.tscn`: composes BoardZone and BoardEventZone.

### Runtime consumers and page composition

- `scripts/card/card_chain_coordinator.gd`: applies chain rules to exact CardInstance values and refreshes Card views.
- `scripts/game/exploration/*.gd`, `scripts/game/event/**/*.gd`, `scripts/game/run/*.gd`: consume `board.board_zone` and `board.event_zone` rather than legacy Board proxies.
- `scripts/game/run/run_card_service.gd`: creates and tracks Card views instead of CardEntity nodes.
- `scripts/game_manager.gd`: configures the persistent zones and owns the only return-to-hand handler.
- `scenes/game/game_manager.tscn`, `scenes/game/hud/hud.tscn`: active page composition with persistent Shop and Reclaim.

---

### Task 1: Make CardInstance the Single Card State Source

**Files:**
- Modify: `scripts/card/card_instance.gd`
- Modify: `scenes/card/card.gd`
- Modify: `tests/card_instance_binding_test.gd`
- Modify: `tests/card_drag_coordinate_test.gd`

**Interfaces:**
- Consumes: existing `CardData`, point/armor labels, artwork TextureRect, and `Card.bind_drag_layer(value: DraggerLayer)`.
- Produces: `CardInstance.ZONE { DRAW, HAND, BOARD, DISCARD, SHOP }`, `Card.bind_card_inst(value: CardInstance) -> void`, `Card.get_card_inst() -> CardInstance`, and `Card.refresh_display() -> void` without `Card.cur_zone`.

- [ ] **Step 1: Write failing state and display tests**

Extend `tests/card_instance_binding_test.gd` with assertions that bind and mutate one exact instance:

```gdscript
func test_card_binds_exact_instance_and_refreshes_all_visuals() -> void:
    var card := CARD_SCENE.instantiate() as Card
    add_child(card)
    await get_tree().process_frame

    var data := CardData.new()
    data.card_name = "First"
    data.card_texture = load("res://assert/card/ribwood_guardian_root.png")
    var instance := CardInstance.new(data)
    instance.current_points = 3
    instance.current_armor = 2

    card.bind_card_inst(instance)
    assert(card.get_card_inst() == instance)
    assert(card.get("cur_zone") == null)
    assert(card.get_node("Points").text == "3")
    assert(card.get_node("Armor").text == "2")
    assert(card.get_node("CardTexture").texture == data.card_texture)

    data.card_texture = load("res://assert/card/ribwood_ember_blade.png")
    instance.current_points = 7
    instance.current_armor = 5
    card.refresh_display()

    assert(card.get_node("Points").text == "7")
    assert(card.get_node("Armor").text == "5")
    assert(card.get_node("CardTexture").texture == data.card_texture)
    card.queue_free()
```

Add enum assertions:

```gdscript
func test_zone_enum_has_shop_and_no_drag_layer() -> void:
    assert(CardInstance.ZONE.has("SHOP"))
    assert(not CardInstance.ZONE.has("DRAGLAYER"))
```

Update `tests/card_drag_coordinate_test.gd` so drag tests bind an instance and never assign `card.cur_zone`.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/card_instance_binding_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/card_drag_coordinate_test.gd
```

Expected: the enum test fails because `SHOP` is absent or `DRAGLAYER` remains, and the Card property assertion fails while `cur_zone` still exists.

- [ ] **Step 3: Implement the minimal state ownership change**

Change `CardInstance.ZONE` to:

```gdscript
enum ZONE {
    DRAW,
    HAND,
    BOARD,
    DISCARD,
    SHOP,
}
```

Delete this field from `scenes/card/card.gd`:

```gdscript
var cur_zone: CardZone
```

Keep one exact instance and refresh immediately:

```gdscript
func bind_card_inst(value: CardInstance) -> void:
    card_inst = value
    refresh_display()

func get_card_inst() -> CardInstance:
    return card_inst

func refresh_display() -> void:
    if card_inst == null or card_inst.card_data == null:
        return
    points_label.text = str(card_inst.current_points)
    armor_label.text = str(card_inst.current_armor)
    _update_artwork()
```

Do not add a replacement zone field to Card.

- [ ] **Step 4: Run focused tests**

Run the two commands from Step 2.

Expected: both tests pass and no script parser error references `Card.cur_zone` in these focused files.

- [ ] **Step 5: Review component documentation and commit**

Before staging, verify every new or materially refactored component in this task has the required Chinese responsibility block and that the text matches the final ownership boundary. Confirm the block names its managed responsibilities, explicit non-responsibilities, usage entry point, and direct dependencies.


```powershell
git add scripts/card/card_instance.gd scenes/card/card.gd tests/card_instance_binding_test.gd tests/card_drag_coordinate_test.gd
git commit -m "refactor: make card instance own card state"
```

---

### Task 2: Add Stable Zone Ownership and Unified Hand Transfers

**Files:**
- Modify: `scripts/zone/card_zone.gd`
- Modify: `scripts/zone/handzone.gd`
- Modify: `tests/card_zone_test.gd`
- Modify: `tests/hand_zone_drop_transfer_test.gd`
- Modify: `tests/hand_zone_insert_test.gd`
- Modify: `tests/hand_zone_rotation_test.gd`

**Interfaces:**
- Consumes: `Card.get_card_inst() -> CardInstance` from Task 1.
- Produces: `CardZone.owns_card(card: Card) -> bool`, `HandZone.add_card(card: Card, keep_global_position: bool = true) -> bool`, stable hand membership, and source snapshot restoration that cannot delete target-created membership.

- [ ] **Step 1: Write failing ownership and hand transaction tests**

Add a base protocol assertion to `tests/card_zone_test.gd`:

```gdscript
func test_base_zone_owns_no_card() -> void:
    var zone := CardZone.new()
    var card := Card.new()
    assert(not zone.owns_card(card))
```

Add to `tests/hand_zone_drop_transfer_test.gd`:

```gdscript
func test_add_card_sets_exact_instance_hand_state() -> void:
    var card := make_card()
    var instance := card.get_card_inst()
    instance.cur_zone = CardInstance.ZONE.BOARD
    instance.battlefield_pos = Vector2i(4, 2)
    instance.direction = 3

    assert(hand_zone.add_card(card, true))
    assert(hand_zone.owns_card(card))
    assert(card.get_card_inst() == instance)
    assert(instance.cur_zone == CardInstance.ZONE.HAND)
    assert(instance.battlefield_pos == Vector2i(-1, -1))
    assert(instance.direction == 0)
    assert(is_zero_approx(card.rotation_degrees))
```

Add a same-zone commit test:

```gdscript
func test_hand_source_commit_keeps_target_reinserted_membership() -> void:
    var card := make_card()
    hand_zone.add_card(card, false)
    hand_zone.start_drag(card)
    assert(not hand_zone.owns_card(card))

    assert(hand_zone.drag_end_target(card, true))
    assert(hand_zone.drag_end_source(card, true))
    assert(hand_zone.owns_card(card))
    assert(hand_zone.get_cards().count(card) == 1)
```

Add cancellation coverage that checks member order, parent, global position, and instance state are restored from the source snapshot.

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/card_zone_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/hand_zone_drop_transfer_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/hand_zone_insert_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/hand_zone_rotation_test.gd
```

Expected: `owns_card()` is undefined, hand state is not fully normalized, or source commit removes the card reinserted by target commit.

- [ ] **Step 3: Implement the ownership protocol and HandZone transaction**

Add the base method:

```gdscript
func owns_card(_card: Card) -> bool:
    return false
```

Implement stable Hand ownership from the member collection:

```gdscript
func owns_card(card: Card) -> bool:
    return card != null and cards.has(card)
```

Make `add_card()` the only Hand receiving entry point:

```gdscript
func add_card(card: Card, keep_global_position: bool = true) -> bool:
    if card == null or card.get_card_inst() == null:
        return false
    var old_global := card.global_position
    if card.get_parent() != self:
        card.reparent(self)
    if keep_global_position:
        card.global_position = old_global
    if not cards.has(card):
        cards.append(card)
    var instance := card.get_card_inst()
    var came_from_board := instance.cur_zone == CardInstance.ZONE.BOARD
    instance.cur_zone = CardInstance.ZONE.HAND
    instance.battlefield_pos = Vector2i(-1, -1)
    if came_from_board:
        instance.direction = 0
    card.rotation_degrees = 0.0
    _schedule_layout()
    return true
```

At `start_drag()`, save the member index, parent, transform, target position, and instance state, then remove the card from `cards` only. On failed source commit restore the snapshot. On successful source commit clear the snapshot without calling `remove_card()` again.

- [ ] **Step 4: Run focused Hand and zone tests**

Run all four commands from Step 2.

Expected: all pass; Hand → Hand contains the card once, and canceled drags restore the exact pre-drag state.

- [ ] **Step 5: Review component documentation and commit**

Before staging, verify every new or materially refactored component in this task has the required Chinese responsibility block and that the text matches the final ownership boundary. Confirm the block names its managed responsibilities, explicit non-responsibilities, usage entry point, and direct dependencies.


```powershell
git add scripts/zone/card_zone.gd scripts/zone/handzone.gd tests/card_zone_test.gd tests/hand_zone_drop_transfer_test.gd tests/hand_zone_insert_test.gd tests/hand_zone_rotation_test.gd
git commit -m "refactor: unify hand zone card ownership"
```

---

### Task 3: Resolve and Cache Drag Sources from Registered Zones

**Files:**
- Modify: `scripts/game/drag_layer/dragger_layer.gd`
- Modify: `tests/dragger_layer_test.gd`
- Modify: `tests/dragger_layer_rotated_card_center_test.gd`
- Modify: `tests/drag_layer_retraction_test.gd`

**Interfaces:**
- Consumes: `CardZone.owns_card(card: Card) -> bool` from Task 2 and the existing registration API.
- Produces: cached `_drag_source: CardZone`, unique source resolution, zero-source support, duplicate-owner rejection, target-first commit, same-zone commit, and cancellation routed to the cached source.

- [ ] **Step 1: Write failing source-resolution tests**

Use a recording zone in `tests/dragger_layer_test.gd`:

```gdscript
class RecordingZone extends CardZone:
    var owned: Array[Card] = []
    var calls: Array[String] = []
    var accept_target := true

    func owns_card(card: Card) -> bool:
        return owned.has(card)

    func start_drag(_card: Card) -> void:
        calls.append("start")

    func can_trans_from_source(_card: Card) -> bool:
        return true

    func can_trans_to_target(_card: Card) -> bool:
        return accept_target

    func drag_end_target(_card: Card, ok: bool) -> bool:
        calls.append("target:%s" % ok)
        return ok

    func drag_end_source(_card: Card, ok: bool) -> bool:
        calls.append("source:%s" % ok)
        return ok
```

Cover four cases:

```gdscript
func test_unique_owner_is_cached_even_after_target_changes_membership() -> void:
    source.owned.append(card)
    dragger.register_zone(source)
    dragger.register_zone(target)
    assert(dragger.start_drag(card))
    source.owned.erase(card)
    target.owned.append(card)
    assert(dragger.end_drag(card))
    assert(target.calls.has("target:true"))
    assert(source.calls.has("source:true"))

func test_duplicate_owners_reject_drag() -> void:
    source.owned.append(card)
    target.owned.append(card)
    assert(not dragger.start_drag(card))

func test_zero_source_can_be_accepted_by_target() -> void:
    assert(dragger.start_drag(card))
    assert(dragger.end_drag(card))
    assert(target.calls.has("target:true"))

func test_same_zone_executes_target_then_source() -> void:
    source.owned.append(card)
    assert(dragger.start_drag(card))
    assert(dragger.end_drag(card))
    assert(source.calls.slice(-2) == ["target:true", "source:true"])
```

Retain the rotated visual-center hit test and update `tests/drag_layer_retraction_test.gd` to use Card ownership rather than `card.cur_zone`.

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/dragger_layer_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/dragger_layer_rotated_card_center_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/drag_layer_retraction_test.gd
```

Expected: the layer still reads `card.cur_zone`, cannot detect duplicate ownership, or skips one side of a same-zone commit.

- [ ] **Step 3: Implement cached source resolution**

Add:

```gdscript
var _drag_source: CardZone

func _resolve_drag_source(card: Card) -> CardZone:
    var owners: Array[CardZone] = []
    for zone in _registered_zones:
        if is_instance_valid(zone) and zone.owns_card(card):
            owners.append(zone)
    if owners.size() > 1:
        push_error("DraggerLayer found multiple owners for Card: %s" % owners)
        return null
    return owners[0] if owners.size() == 1 else null
```

At drag start, separately count owners so “no owner” remains valid while “multiple owners” rejects the drag. Cache the unique source before calling `start_drag(card)`. At drag end:

```gdscript
if target != null and target_ok:
    target.drag_end_target(card, true)
    if _drag_source != null:
        _drag_source.drag_end_source(card, true)
else:
    if target != null:
        target.drag_end_target(card, false)
    if _drag_source != null:
        _drag_source.drag_end_source(card, false)
_drag_source = null
```

Do not recalculate source after target commit. Do not special-case `target == _drag_source`.

- [ ] **Step 4: Run drag tests**

Run all three commands from Step 2.

Expected: all pass; target commit is recorded before source commit, and rotated-card targeting remains unchanged.

- [ ] **Step 5: Review component documentation and commit**

Before staging, verify every new or materially refactored component in this task has the required Chinese responsibility block and that the text matches the final ownership boundary. Confirm the block names its managed responsibilities, explicit non-responsibilities, usage entry point, and direct dependencies.


```powershell
git add scripts/game/drag_layer/dragger_layer.gd tests/dragger_layer_test.gd tests/dragger_layer_rotated_card_center_test.gd tests/drag_layer_retraction_test.gd
git commit -m "refactor: resolve drag sources from zone ownership"
```

---

### Task 4: Migrate Persistent Shop and Reclaim Transactions to CardInstance State

**Files:**
- Modify: `scripts/zone/shop_zone.gd`
- Modify: `scripts/zone/shop.gd`
- Modify: `scripts/zone/reclaim_zone.gd`
- Modify: `tests/shop_zone_purchase_test.gd`
- Modify: `tests/shop_scene_test.gd`
- Modify: `tests/reclaim_zone_test.gd`

**Interfaces:**
- Consumes: Task 1 CardInstance state, Task 2 ownership protocol, Task 3 target-first commit.
- Produces: `ShopZone.owns_card(card: Card) -> bool`, stable product slots with SHOP state, exact-instance purchase completion/restock, and stateless `ReclaimZone.owns_card(card: Card) -> bool == false` with HAND-only validation.

- [ ] **Step 1: Write failing Shop and Reclaim tests**

Add Shop stable-state coverage:

```gdscript
func test_product_slot_owns_card_and_sets_shop_state() -> void:
    var card := make_bound_card()
    var instance := card.get_card_inst()
    shop_zone.set_products([card])
    assert(shop_zone.owns_card(card))
    assert(instance.cur_zone == CardInstance.ZONE.SHOP)
    assert(instance.battlefield_pos == Vector2i(-1, -1))
    assert(instance.direction == 0)
```

Add exact-instance purchase coverage:

```gdscript
func test_successful_purchase_preserves_target_membership_and_emits_exact_instance() -> void:
    var purchased: Array = []
    shop_zone.product_purchased.connect(func(card: Card, instance: CardInstance, slot: int):
        purchased.append([card, instance, slot])
    )
    var card := make_bound_card()
    var instance := card.get_card_inst()
    shop_zone.set_products([card])
    shop_zone.start_drag(card)
    hand_zone.drag_end_target(card, true)
    shop_zone.drag_end_source(card, true)
    assert(hand_zone.owns_card(card))
    assert(not shop_zone.owns_card(card))
    assert(purchased == [[card, instance, 0]])
```

Add Reclaim checks:

```gdscript
func test_reclaim_is_never_a_stable_owner_and_accepts_only_hand_instance() -> void:
    var card := make_bound_card()
    assert(not reclaim_zone.owns_card(card))
    card.get_card_inst().cur_zone = CardInstance.ZONE.BOARD
    assert(not reclaim_zone.can_reclaim(card))
    card.get_card_inst().cur_zone = CardInstance.ZONE.HAND
    assert(reclaim_zone.can_reclaim(card))
```

Extend the existing reclaim success test to assert one gold award, one RunCardService destruction call, `cur_zone == DISCARD`, `battlefield_pos == (-1, -1)`, and `direction == 0`.

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/shop_zone_purchase_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/shop_scene_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/reclaim_zone_test.gd
```

Expected: Shop/Reclaim still read `card.cur_zone`, Shop lacks stable ownership, or successful source commit removes a card already accepted by Hand/Board.

- [ ] **Step 3: Implement ShopZone and ReclaimZone state rules**

Implement Shop ownership and stable adoption:

```gdscript
func owns_card(card: Card) -> bool:
    return card != null and _products.has(card)

func _set_shop_state(card: Card) -> void:
    var instance := card.get_card_inst()
    instance.cur_zone = CardInstance.ZONE.SHOP
    instance.battlefield_pos = Vector2i(-1, -1)
    instance.direction = 0
    card.rotation_degrees = 0.0
```

Call `_set_shop_state()` whenever a product enters a stable slot. On `start_drag()`, save the slot and remove the stable membership. On canceled source commit, restore the same slot. On successful source commit, emit `product_purchased(card, card.get_card_inst(), slot)` and clear the snapshot without deleting or reparenting the card.

Keep Shop responsible for purchase validation, exact instance registration, payment, slot replacement, and restock after `product_purchased`. When Shop updates an existing CardInstance, call `card.refresh_display()`.

Implement Reclaim ownership and validation:

```gdscript
func owns_card(_card: Card) -> bool:
    return false

func can_reclaim(card: Card) -> bool:
    return card != null \
        and card.get_card_inst() != null \
        and card.get_card_inst().cur_zone == CardInstance.ZONE.HAND \
        and _card_service.can_destroy_existing_instance(card.get_card_inst(), card)
```

On successful target commit, perform the existing gold and destruction operations exactly once, then normalize the exact instance to DISCARD state before freeing the Card view.

- [ ] **Step 4: Run Shop/Reclaim tests**

Run all three commands from Step 2.

Expected: all pass; Shop → Hand/Board keeps target membership and exact instance, while Reclaim stays a stateless target.

- [ ] **Step 5: Review component documentation and commit**

Before staging, verify every new or materially refactored component in this task has the required Chinese responsibility block and that the text matches the final ownership boundary. Confirm the block names its managed responsibilities, explicit non-responsibilities, usage entry point, and direct dependencies.


```powershell
git add scripts/zone/shop_zone.gd scripts/zone/shop.gd scripts/zone/reclaim_zone.gd tests/shop_zone_purchase_test.gd tests/shop_scene_test.gd tests/reclaim_zone_test.gd
git commit -m "refactor: migrate shop and reclaim card state"
```

---

### Task 5: Introduce Board Spatial Operation DTOs and Card-Based Public Results

**Files:**
- Create: `scripts/game/board_card_placement.gd`
- Create: `scripts/game/board_card_retraction.gd`
- Modify: `scripts/game/board_placement_result.gd`
- Modify: `scripts/game/chain_retraction_transaction.gd`
- Create: `tests/board_operation_dto_test.gd`
- Modify: `tests/board_placement_transaction_test.gd`

**Interfaces:**
- Consumes: `Card` and exact `CardInstance` from Task 1.
- Produces: `BoardCardPlacement`, `BoardCardRetraction`, Card-based `BoardPlacementResult`, and Card-based `ChainRetractionTransaction`.

- [ ] **Step 1: Write failing DTO type tests**

Create `tests/board_operation_dto_test.gd` with:

```gdscript
extends SceneTree

func _init() -> void:
    var card := Card.new()
    var instance := CardInstance.new(CardData.new())
    card.bind_card_inst(instance)

    var placement := BoardCardPlacement.new()
    placement.card = card
    placement.card_inst = instance
    placement.kind = BoardCardPlacement.Kind.GUIDE_SHIFTED
    placement.occupied_cells = [Vector2i(1, 2)]
    placement.affected_cards = [card]
    placement.chain_tail = card
    assert(placement.card == card)
    assert(placement.card_inst == instance)

    var retraction := BoardCardRetraction.new()
    retraction.removed_card = card
    retraction.followers_to_return = [card]
    retraction.original_chain_size = 2
    assert(retraction.followers_to_return[0] is Card)

    var result := BoardPlacementResult.new(
        BoardPlacementResult.Kind.GUIDE_RESOLVED,
        card,
        card,
        [card],
        [Vector2i(1, 2)],
        null
    )
    assert(result.source_card is Card)

    var transaction := ChainRetractionTransaction.new(card, [card], 2)
    assert(transaction.removed_card is Card)
    quit()
```

Update `tests/board_placement_transaction_test.gd` constructors to use Card rather than CardEntity.

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/board_operation_dto_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/board_placement_transaction_test.gd
```

Expected: the new DTO classes are missing and public result properties still require CardEntity.

- [ ] **Step 3: Create the DTOs and migrate public types**

Create `scripts/game/board_card_placement.gd`:

```gdscript
class_name BoardCardPlacement
extends RefCounted

enum Kind {
    CHAIN_EXTENDED,
    GUIDE_SHIFTED,
}

var card: Card
var card_inst: CardInstance
var kind: Kind
var occupied_cells: Array[Vector2i]
var affected_cards: Array[Card]
var chain_tail: Card
```

Create `scripts/game/board_card_retraction.gd`:

```gdscript
class_name BoardCardRetraction
extends RefCounted

var removed_card: Card
var followers_to_return: Array[Card]
var original_chain_size: int
```

Change these exact public properties and constructor parameters:

```gdscript
# BoardPlacementResult
var source_card: Card
var chain_tail: Card
var affected_cards: Array[Card]

# ChainRetractionTransaction
var removed_card: Card
var returned_followers: Array[Card]
```

Keep existing enum names and business result field names.

- [ ] **Step 4: Run DTO tests**

Run both commands from Step 2.

Expected: both pass with no CardEntity type errors.

- [ ] **Step 5: Review component documentation and commit**

Before staging, verify every new or materially refactored component in this task has the required Chinese responsibility block and that the text matches the final ownership boundary. Confirm the block names its managed responsibilities, explicit non-responsibilities, usage entry point, and direct dependencies.


```powershell
git add scripts/game/board_card_placement.gd scripts/game/board_card_retraction.gd scripts/game/board_placement_result.gd scripts/game/chain_retraction_transaction.gd tests/board_operation_dto_test.gd tests/board_placement_transaction_test.gd
git commit -m "refactor: add card based board operation dtos"
```

---
### Task 6: Refactor BoardZone Card Placement, GUIDE, and Chain Retraction

**Files:**
- Modify: `scripts/zone/board_zone.gd`
- Modify: `tests/board_zone_test.gd`
- Modify: `tests/board_direction_test.gd`
- Modify: `tests/guide_card_test.gd`
- Modify: `tests/board_placement_transaction_test.gd`

**Interfaces:**
- Consumes: `BoardCardPlacement` and `BoardCardRetraction` from Task 5, `CardZone.owns_card()`, and CardInstance state.
- Produces: `signal placement_applied(operation: BoardCardPlacement)`, `signal chain_segment_detached(operation: BoardCardRetraction)`, Card-based `get_cards()`, `get_combat_card_chain()`, `get_card_cells(card: Card)`, `get_placement_cell(card: Card)`, `can_place_card(card: Card, ...)`, and target/source drag methods without HandZone calls.

- [ ] **Step 1: Write failing BoardZone transaction tests**

Extend `tests/board_zone_test.gd` with ownership and operation assertions:

```gdscript
func test_board_zone_owns_only_stable_board_cards() -> void:
    var card := make_card()
    card.get_card_inst().cur_zone = CardInstance.ZONE.BOARD
    board_zone.add_card(card)
    assert(board_zone.owns_card(card))
    board_zone.start_drag(card)
    assert(not board_zone.owns_card(card))
    board_zone.drag_end_source(card, false)
    assert(board_zone.owns_card(card))
```

Add signal capture:

```gdscript
func test_normal_and_guide_emit_one_structured_placement() -> void:
    var operations: Array[BoardCardPlacement] = []
    board_zone.placement_applied.connect(func(operation: BoardCardPlacement): operations.append(operation))
    var root := make_root_card()
    assert(board_zone.drag_end_target(root, true))
    assert(operations.size() == 1)
    assert(operations[0].kind == BoardCardPlacement.Kind.CHAIN_EXTENDED)

    operations.clear()
    var guide := make_guide_card()
    assert(board_zone.drag_end_target(guide, true))
    assert(operations.size() == 1)
    assert(operations[0].kind == BoardCardPlacement.Kind.GUIDE_SHIFTED)
    assert(not board_zone.owns_card(guide))
```

Add chain-detach ordering:

```gdscript
func test_detached_followers_are_emitted_in_original_chain_order() -> void:
    var retractions: Array[BoardCardRetraction] = []
    board_zone.chain_segment_detached.connect(func(operation: BoardCardRetraction): retractions.append(operation))
    var chain := make_chain(4)
    assert(board_zone.remove_card(chain[1]))
    assert(retractions.size() == 1)
    assert(retractions[0].removed_card == chain[1])
    assert(retractions[0].followers_to_return == [chain[2], chain[3]])
```

Keep existing ROOT, normal-tail, invalid-middle, cancellation, direction, and cell-occupancy tests, changing all card types to Card.

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/board_zone_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/board_direction_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/guide_card_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/board_placement_transaction_test.gd
```

Expected: BoardZone still calls HandZone for GUIDE/follower return, lacks structured signals, or uses old CardEntity/`Card.cur_zone` state.

- [ ] **Step 3: Implement BoardZone ownership and synchronous operations**

Add:

```gdscript
signal placement_applied(operation: BoardCardPlacement)
signal chain_segment_detached(operation: BoardCardRetraction)

func owns_card(card: Card) -> bool:
    return card != null and cards.has(card)
```

When a card is stably committed, update the exact instance before emitting:

```gdscript
func _commit_card_layout(card: Card, cells: Array[Vector2i]) -> void:
    _release_card_cells(card)
    for cell in cells:
        _grid_owner[cell] = card
    if not cards.has(card):
        cards.append(card)
    var instance := card.get_card_inst()
    instance.cur_zone = CardInstance.ZONE.BOARD
    instance.battlefield_pos = _placement_origin_for(cells)
    instance.direction = _card_direction(card)
    card.refresh_display()

func _placement_origin_for(cells: Array[Vector2i]) -> Vector2i:
    return cells[0] if not cells.is_empty() else Vector2i(-1, -1)
```

Use `_remove_dragged_card_from_board(card)` only for the source snapshot and never remove a target-created membership from source commit. For GUIDE, move affected stable chain cards, emit `BoardCardPlacement` with `GUIDE_SHIFTED`, and leave the GUIDE outside `cards`.

For chain removal, detach the selected card and followers in original order, clear their cells and stable membership, create `BoardCardRetraction`, and emit exactly once. Do not call `HandZone`, `RunCardService`, or `Board` from BoardZone. The page-level Board handler will return follower cards later.

- [ ] **Step 4: Run BoardZone tests**

Run all four commands from Step 2.

Expected: all pass; BoardZone owns only stable Board cards, updates CardInstance coordinates/direction, emits one operation per successful action, and never directly returns cards to HandZone.

- [ ] **Step 5: Review component documentation and commit**

Before staging, verify every new or materially refactored component in this task has the required Chinese responsibility block and that the text matches the final ownership boundary. Confirm the block names its managed responsibilities, explicit non-responsibilities, usage entry point, and direct dependencies.


```powershell
git add scripts/zone/board_zone.gd tests/board_zone_test.gd tests/board_direction_test.gd tests/guide_card_test.gd tests/board_placement_transaction_test.gd
git commit -m "refactor: isolate board zone card transactions"
```

---

### Task 7: Extract BoardEventZone and Preserve Event Spatial Semantics

**Files:**
- Create: `scripts/zone/board_event_zone.gd`
- Create: `scenes/zone/board_event_zone.tscn`
- Create: `tests/board_event_zone_test.gd`
- Modify: `tests/event_trigger_test.gd`
- Modify: `tests/event_spawn_candidate_test.gd`

**Interfaces:**
- Consumes: the existing Board grid dimensions and `BoardEvent`/`EventInstance` APIs currently implemented in `scripts/game/board.gd`.
- Produces: `BoardEventZone.width`, `BoardEventZone.height`, `BoardEventZone.cell_size`, `get_event_cells(origin, event_size)`, `get_event_buffer_cells(origin, event_size)`, `can_attach_event(instance)`, `attach_event(event_node)`, `move_event(event_node, target_origin)`, `remove_event(event_node)`, `get_overlapping_unresolved_event(card_cells)`, and `get_events() -> Array[BoardEvent]`.

- [ ] **Step 1: Write failing event-zone tests**

Create `tests/board_event_zone_test.gd`:

```gdscript
func test_event_zone_exposes_shared_grid_geometry() -> void:
    assert(event_zone.width == grid_source.grid_width)
    assert(event_zone.height == grid_source.grid_height)
    assert(is_equal_approx(event_zone.cell_size, grid_source.cell_size))

func test_event_cells_and_buffer_match_old_board_rules() -> void:
    assert(event_zone.get_event_cells(Vector2i(2, 1), Vector2i(2, 2)) == [
        Vector2i(2, 1), Vector2i(3, 1), Vector2i(2, 2), Vector2i(3, 2)
    ])
    assert(event_zone.get_event_buffer_cells(Vector2i(2, 1), Vector2i(2, 2)).size() > 4)
    assert(event_zone.get_event_cells(Vector2i(-1, 0), Vector2i(2, 2)).is_empty())

func test_failed_event_operations_do_not_mutate_index_or_instance_origin() -> void:
    var instance := make_event_instance(Vector2i(2, 2))
    var node := make_event_node(instance)
    assert(not event_zone.attach_event(node))
    assert(event_zone.get_events().is_empty())
    assert(instance.origin == Vector2i(2, 2))

func test_successful_add_move_remove_updates_index_once() -> void:
    var instance := make_event_instance(Vector2i(1, 1))
    var node := make_event_node(instance)
    assert(event_zone.attach_event(node))
    assert(event_zone.get_events() == [node])
    assert(event_zone.move_event(node, Vector2i(3, 2)))
    assert(instance.origin == Vector2i(3, 2))
    assert(event_zone.remove_event(node))
    assert(event_zone.get_events().is_empty())

func test_overlap_returns_only_unresolved_event_instances() -> void:
    var node := make_event_node(make_event_instance(Vector2i(1, 1)))
    assert(event_zone.attach_event(node))
    assert(event_zone.get_overlapping_unresolved_event([Vector2i(1, 1)]) == node.event_instance)
    node.event_instance.resolved = true
    assert(event_zone.get_overlapping_unresolved_event([Vector2i(1, 1)]) == null)
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/board_event_zone_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/event_trigger_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/event_spawn_candidate_test.gd
```

Expected: the new scene/script is absent and event-space calls still resolve to Board's legacy implementation.

- [ ] **Step 3: Implement the extracted event grid**

Create `BoardEventZone` as a `Node2D` or `Control` matching the shared BoardZone coordinate system. Keep the grid source as the single geometry owner:

```gdscript
@export var grid_source: BoardZoneBG

var width: int:
    get:
        return grid_source.grid_width

var height: int:
    get:
        return grid_source.grid_height

var cell_size: float:
    get:
        return grid_source.cell_size

var _events: Array[BoardEvent] = []
var _event_grid_owner: Dictionary[Vector2i, BoardEvent] = {}
```

Copy the old bounds/buffer formulas exactly into the new methods. For add/move, calculate all cells first, check bounds and collisions, then mutate `_event_grid_owner`, node parent/position, and `EventInstance.origin` only after validation succeeds. For failure, leave all three unchanged. Remove uses the indexed node identity and frees no externally-owned resource unless the existing BoardEvent lifecycle requires it.

Implement `get_overlapping_unresolved_event(card_cells)` by iterating indexed cells, deduplicating nodes, and ignoring resolved instances.

- [ ] **Step 4: Run event-zone tests**

Run all three commands from Step 2.

Expected: all pass and event placement behavior is unchanged.

- [ ] **Step 5: Review component documentation and commit**

Before staging, verify every new or materially refactored component in this task has the required Chinese responsibility block and that the text matches the final ownership boundary. Confirm the block names its managed responsibilities, explicit non-responsibilities, usage entry point, and direct dependencies.


```powershell
git add scripts/zone/board_event_zone.gd scenes/zone/board_event_zone.tscn tests/board_event_zone_test.gd tests/event_trigger_test.gd tests/event_spawn_candidate_test.gd
git commit -m "refactor: extract board event zone"
```

---
### Task 8: Rebuild Board as a Business Coordinator and Compose board.tscn

**Files:**
- Modify: `scripts/game/board.gd`
- Modify: `scenes/game/board.tscn`
- Modify: `tests/board_placement_transaction_test.gd`
- Modify: `tests/event_trigger_test.gd`
- Create: `tests/board_scene_composition_test.gd`

**Interfaces:**
- Consumes: BoardZone operation signals from Task 6 and BoardEventZone APIs from Task 7.
- Produces: `@export var board_zone: BoardZone`, `@export var event_zone: BoardEventZone`, existing business signals `placement_committed`, `card_return_requested`, `chain_retraction_confirmed`, `event_triggered`, `event_attached`, `event_removed`, and existing business entry points `attach_event`, `move_event`, `remove_event`.

- [ ] **Step 1: Write failing Board composition and signal-order tests**

Create `tests/board_scene_composition_test.gd`:

```gdscript
func test_board_scene_contains_independent_zones() -> void:
    var board := BOARD_SCENE.instantiate() as Board
    add_child(board)
    assert(board.board_zone is BoardZone)
    assert(board.event_zone is BoardEventZone)
    assert(board.get_node_or_null("BoardZone") == board.board_zone)
    assert(board.get_node_or_null("BoardEventZone") == board.event_zone)
    assert(not board.has_method("get_card_cells"))
    assert(not board.has_method("get_event_cells"))
```

Add business ordering coverage:

```gdscript
func test_guide_commits_before_return_request() -> void:
    var order: Array[String] = []
    board.placement_committed.connect(func(_result): order.append("placement"))
    board.card_return_requested.connect(func(_card): order.append("return"))
    var guide := make_guide_card()
    board.board_zone.prepare_test_drop(guide)
    assert(board.board_zone.drag_end_target(guide, true))
    assert(order == ["placement", "return"])
```

Add chain-return coverage that feeds followers through a callback and asserts `chain_retraction_confirmed` fires only after every follower has `cur_zone == HAND`.

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/board_scene_composition_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/board_placement_transaction_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/event_trigger_test.gd
```

Expected: Board still owns legacy card/event grids, has `card_placed`, lacks `chain_retraction_confirmed`, or does not translate the new operation signals.

- [ ] **Step 3: Implement Board coordination and scene composition**

Declare:

```gdscript
class_name Board
extends Node

@export var board_zone: BoardZone
@export var event_zone: BoardEventZone

signal placement_committed(result: BoardPlacementResult)
signal card_return_requested(card: Card)
signal chain_retraction_confirmed(transaction: ChainRetractionTransaction)
signal event_triggered(instance: EventInstance)
signal event_attached(event_node: BoardEvent)
signal event_removed(event_node: BoardEvent)
```

Remove `card_placed` and all legacy `_grid_owner` / `_event_grid_owner` fields. Connect child-zone signals in `_ready()`.

Translate `BoardCardPlacement.Kind.CHAIN_EXTENDED` into `BoardPlacementResult.Kind.CHAIN_EXTENDED`; translate GUIDE into `GUIDE_RESOLVED`. Query `event_zone.get_overlapping_unresolved_event(operation.occupied_cells)` and store the returned instance in `overlapped_event`. Emit `placement_committed` once, then emit `card_return_requested(operation.card)` for GUIDE only.

For `chain_segment_detached`, create `ChainRetractionTransaction`, emit one `card_return_requested(follower)` in original order per follower, and verify each follower now has `cur_zone == HAND` before emitting `chain_retraction_confirmed`. Do not request return for the directly dragged card.

Keep Board business methods:

```gdscript
func attach_event(event_node: BoardEvent) -> bool:
    if not event_zone.attach_event(event_node):
        return false
    event_attached.emit(event_node)
    return true

func move_event(event_node: BoardEvent, target_origin: Vector2i) -> bool:
    return event_zone.move_event(event_node, target_origin)

func remove_event(event_node: BoardEvent) -> bool:
    if not event_zone.remove_event(event_node):
        return false
    event_removed.emit(event_node)
    return true
```

Do not add Board wrappers for `get_combat_card_chain`, `get_event_cells`, `can_attach_event`, `get_cards`, or `set_drag_layer`.

Compose `scenes/game/board.tscn` with Board as the root and BoardZone/BoardEventZone as child nodes, wiring exported properties to the exact child nodes.

- [ ] **Step 4: Run Board and event tests**

Run all three commands from Step 2 plus:

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/board_zone_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/guide_card_test.gd
```

Expected: all pass; Board is only the business coordinator and preserves signal ordering.

- [ ] **Step 5: Review component documentation and commit**

Before staging, verify every new or materially refactored component in this task has the required Chinese responsibility block and that the text matches the final ownership boundary. Confirm the block names its managed responsibilities, explicit non-responsibilities, usage entry point, and direct dependencies.


```powershell
git add scripts/game/board.gd scenes/game/board.tscn tests/board_placement_transaction_test.gd tests/event_trigger_test.gd tests/board_scene_composition_test.gd
git commit -m "refactor: compose board from card and event zones"
```

---

### Task 9: Migrate Board Consumers and RunCardService to Card/CardInstance APIs

**Files:**
- Modify: `scripts/card/card_chain_coordinator.gd`
- Modify: `scripts/game/exploration/boss_pressure_service.gd`
- Modify: `scripts/game/exploration/exploration_event_service.gd`
- Modify: `scripts/game/exploration/exploration_coordinator.gd`
- Modify: `scripts/game/event/core/event_placement_service.gd`
- Modify: `scripts/game/event/hover/event_hover_preview_coordinator.gd`
- Modify: `scripts/game/event/encounter/encounter_resolution_coordinator.gd`
- Modify: `scripts/game/run/run_flow_coordinator.gd`
- Modify: `scripts/game/run/run_card_service.gd`
- Modify: `scripts/game/run/run_setup_coordinator.gd`
- Modify: `scripts/game/placement/placement_pipeline_coordinator.gd`
- Modify: `scripts/game_manager.gd`
- Modify: `tests/card_chain_coordinator_test.gd`
- Modify: `tests/boss_pressure_board_test.gd`
- Modify: `tests/exploration_event_spawn_test.gd`
- Modify: `tests/event_hover_preview_coordinator_test.gd`
- Modify: `tests/encounter_resolution_coordinator_test.gd`
- Modify: `tests/run_card_service_test.gd`
- Modify: `tests/run_card_service_existing_instance_test.gd`
- Modify: `tests/run_card_service_destroy_existing_instance_test.gd`
- Modify: `tests/placement_pipeline_coordinator_test.gd`
- Modify: `tests/run_flow_coordinator_test.gd`

**Interfaces:**
- Consumes: `board.board_zone`, `board.event_zone`, Card-based Board DTOs, and exact `CardInstance` state from Tasks 1 and 8.
- Produces: active consumers that never use Board spatial proxies, never access `Card.cur_zone`, and a `RunCardService.configure(card_scene: PackedScene, hand_zone: HandZone, drag_layer: DraggerLayer)` path that creates only Card views.

- [ ] **Step 1: Write failing migration assertions**

Add source-level architecture assertions to `tests/run_card_service_test.gd`:

```gdscript
func test_new_card_service_registers_card_view_and_exact_instance() -> void:
    var service := RunCardService.new()
    service.configure(CARD_SCENE, hand_zone, drag_layer)
    assert(service.initialize_starting_deck(starting_deck))
    assert(service.get_card_views().all(func(view): return view is Card))
    for view in service.get_card_views():
        assert(view.get_card_inst() in service.get_instances())
        assert(view.get_card_inst() != null)
        assert(view.get_parent() == hand_zone or view.get_parent() == board.board_zone)
```

Add a test that mutating `card.get_card_inst().current_points` and calling `card.refresh_display()` updates the visible labels after a consumer operation.

Update `tests/boss_pressure_board_test.gd` and `tests/placement_pipeline_coordinator_test.gd` to pass a Board with child zones and assert calls go through `board.board_zone` / `board.event_zone`.

Add a search-based regression test script or CI command that fails if production files contain `card.cur_zone`, `board.get_event_cells`, `board.get_card_cells`, `board.get_cards`, or `board.get_combat_card_chain`.

- [ ] **Step 2: Run migration tests to verify they fail**

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/run_card_service_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/run_card_service_existing_instance_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/run_card_service_destroy_existing_instance_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/boss_pressure_board_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/placement_pipeline_coordinator_test.gd
```

Expected: RunCardService still requires CardManager/HandArea/CardEntity, and consumers still call removed Board proxy methods.

- [ ] **Step 3: Migrate consumers in dependency order**

First change `CardChainCoordinator` to receive `Card`, read `var instance := card.get_card_inst()`, apply rules to that instance, and call `card.refresh_display()` after changes. Remove calls to the nonexistent `refresh_combat_tags()` API.

Then update Board consumers:

```gdscript
var cards: Array[Card] = board.board_zone.get_cards()
var chain: Array[Card] = board.board_zone.get_combat_card_chain()
var cells: Array[Vector2i] = board.board_zone.get_card_cells(card)
var placement_cell := board.board_zone.get_placement_cell(card)
var event_zone := board.event_zone
var events: Array[BoardEvent] = event_zone.get_events()
```

Update `EventPlacementService` to use `event_zone.width`, `event_zone.height`, `event_zone.cell_size`, `event_zone.get_event_cells()`, and `event_zone.can_attach_event()`; keep the business call `board.attach_event(event_node)`.

Update `EncounterResolutionCoordinator` to locate exact Cards from `board.board_zone.get_cards()`, call `board.board_zone.remove_card(card)`, mutate the exact `CardInstance`, and refresh the Card display.

Rewrite `RunCardService` configuration and creation path:

```gdscript
func configure(card_scene: PackedScene, hand_zone: HandZone, drag_layer: DraggerLayer) -> void:
    _card_scene = card_scene
    _hand_zone = hand_zone
    _drag_layer = drag_layer

func _create_view(instance: CardInstance) -> Card:
    var card := _card_scene.instantiate() as Card
    card.bind_card_inst(instance)
    card.bind_drag_layer(_drag_layer)
    return card
```

Keep existing public method names, changing the active flow's card parameter types to Card:

```gdscript
func return_existing_to_hand(card: Card, allow_overflow := false) -> bool
func return_existing_to_hand_temporarily(card: Card) -> bool
func destroy_existing_card(card: Card) -> bool
func get_card_views() -> Array[Card]
```

`allow_overflow` remains a compatibility parameter; do not reintroduce `HandArea.max_hand_size`. `initialize_starting_deck()` and grant methods create `CardInstance`, create one Card view, bind exact instance and drag layer, then call `hand_zone.add_card(card)`.

Remove the RunFlowCoordinator connection that independently handles `Board.card_return_requested`; leave the page-level handler for Task 10.

- [ ] **Step 4: Run migrated consumer tests and full script validation**

Run all commands from Step 2, then:

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/card_chain_coordinator_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/exploration_event_spawn_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/event_hover_preview_coordinator_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/encounter_resolution_coordinator_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/run_flow_coordinator_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/placement_pipeline_coordinator_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/game_manager_architecture_test.gd
```

Expected: all pass; `Card.cur_zone` and removed Board proxy references are absent from the active production path.

- [ ] **Step 5: Review component documentation and commit**

Before staging, verify every new or materially refactored component in this task has the required Chinese responsibility block and that the text matches the final ownership boundary. Confirm the block names its managed responsibilities, explicit non-responsibilities, usage entry point, and direct dependencies.


```powershell
git add scripts/card/card_chain_coordinator.gd scripts/game/exploration/boss_pressure_service.gd scripts/game/exploration/exploration_event_service.gd scripts/game/exploration/exploration_coordinator.gd scripts/game/event/core/event_placement_service.gd scripts/game/event/hover/event_hover_preview_coordinator.gd scripts/game/event/encounter/encounter_resolution_coordinator.gd scripts/game/run/run_flow_coordinator.gd scripts/game/run/run_card_service.gd scripts/game/run/run_setup_coordinator.gd scripts/game/placement/placement_pipeline_coordinator.gd scripts/game_manager.gd tests/card_chain_coordinator_test.gd tests/boss_pressure_board_test.gd tests/exploration_event_spawn_test.gd tests/event_hover_preview_coordinator_test.gd tests/encounter_resolution_coordinator_test.gd tests/run_card_service_test.gd tests/run_card_service_existing_instance_test.gd tests/run_card_service_destroy_existing_instance_test.gd tests/placement_pipeline_coordinator_test.gd tests/run_flow_coordinator_test.gd
git commit -m "refactor: migrate board consumers to card zones"
```

---
### Task 10: Reassemble the Persistent Game Page and Run Full Regression

**Files:**
- Modify: `scripts/game_manager.gd`
- Modify: `scenes/game/game_manager.tscn`
- Modify: `scenes/game/hud/hud.tscn`
- Modify: `scripts/zone/shop.gd`
- Modify: `tests/game_manager_architecture_test.gd`
- Modify: `tests/game_manager_run_setup_test.gd`
- Modify: `tests/game_manager_event_contact_test.gd`
- Modify: `tests/game_manager_persistent_market_test.gd`
- Create: `tests/game_page_zone_composition_test.gd`
- Modify: `tests/persistent_market_scene_test.gd`
- Modify: `tests/persistent_market_drag_test.gd`

**Interfaces:**
- Consumes: the Card/zone APIs from Tasks 1–4, Board scene and business signals from Task 8, and Card-based RunCardService from Task 9.
- Produces: the active persistent page with one DraggerLayer, HandZone, Board, Shop/ShopZone, and ReclaimZone; one return-to-hand handler; and no active PersistentMarket/CardManager/HandArea board path.

- [ ] **Step 1: Write failing scene-composition and routing tests**

Create `tests/game_page_zone_composition_test.gd`:

```gdscript
func test_active_page_has_one_drag_layer_and_persistent_zones() -> void:
    var page := GAME_MANAGER_SCENE.instantiate()
    add_child(page)
    assert(page.get_node("GameplayCanvas/DragLayer") is DraggerLayer)
    assert(page.get_node("GameplayCanvas/Hud/Board") is Board)
    assert(page.get_node("GameplayCanvas/Hud/HandZone") is HandZone)
    assert(page.get_node("GameplayCanvas/Hud/Shop") is Shop)
    assert(page.get_node("GameplayCanvas/Hud/ReclaimZone") is ReclaimZone)
    assert(page.get_node("GameplayCanvas/Hud/Board/BoardZone") is BoardZone)
    assert(page.get_node("GameplayCanvas/Hud/Board/BoardEventZone") is BoardEventZone)
    assert(page.find_children("*", "DraggerLayer", true, false).size() == 1)

func test_all_card_zones_share_the_same_drag_layer() -> void:
    var page := GAME_MANAGER_SCENE.instantiate()
    add_child(page)
    var drag_layer := page.get_node("GameplayCanvas/DragLayer")
    for zone_path in ["GameplayCanvas/Hud/HandZone", "GameplayCanvas/Hud/Board/BoardZone", "GameplayCanvas/Hud/Shop/ShopZone", "GameplayCanvas/Hud/ReclaimZone"]:
        assert(page.get_node(zone_path) in drag_layer.get_registered_zones())

func test_board_return_has_one_page_handler() -> void:
    var page := GAME_MANAGER_SCENE.instantiate()
    add_child(page)
    var board := page.get_node("GameplayCanvas/Hud/Board") as Board
    assert(board.card_return_requested.get_connections().size() == 1)
```

Update `tests/game_manager_architecture_test.gd` to assert `PersistentMarket`, `CardManager`, and `HandArea` are not in the active page tree. Keep old PersistentMarket tests isolated to the legacy scene only; new page tests must instantiate `Shop`.

- [ ] **Step 2: Run page tests to verify they fail**

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/game_page_zone_composition_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/game_manager_architecture_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/game_manager_run_setup_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/game_manager_event_contact_test.gd
```

Expected: the active page still instantiates the legacy market/CardManager/HandArea path, contains more than one drag layer, or has duplicate return handlers.

- [ ] **Step 3: Recompose scenes and configure runtime ownership**

Change the scene tree to:

```text
GameManager
└── GameplayCanvas
    ├── Hud
    │   ├── Board
    │   │   ├── BoardZone
    │   │   └── BoardEventZone
    │   ├── HandZone
    │   ├── Shop
    │   │   └── ShopZone
    │   └── ReclaimZone
    └── DragLayer
```

Remove active `PersistentMarket`, `CardManager`, and `HandArea` instances. Do not remove or overwrite the user's unrelated scene edits; preserve existing HUD/card presentation nodes while replacing only the old zone composition.

In `scripts/game_manager.gd`, configure the single drag layer into all zones, configure Shop with the current pricing/player/card service dependencies, and configure Reclaim with the same existing services. Register the zones once and bind every Card created by RunCardService and Shop to the same drag layer.

Implement the only return handler:

```gdscript
func _on_board_card_return_requested(card: Card) -> void:
    if not hand_zone.add_card(card, true):
        push_error("GameManager failed to return Card to HandZone")
```

Connect `board.card_return_requested` in GameManager only. Do not connect it in RunFlowCoordinator or another coordinator.

Update Shop scene wiring so Shop remains resident and directly manages ShopZone refresh/restock. Its external function names and purchase semantics remain unchanged. After a successful purchase, Shop performs registration/payment/restock once and refreshes the purchased/replacement Card display.

- [ ] **Step 4: Run complete regression and static checks**

Run page and architecture tests:

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/game_page_zone_composition_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/game_manager_architecture_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/game_manager_run_setup_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/game_manager_event_contact_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/shop_scene_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/shop_zone_purchase_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/reclaim_zone_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/board_zone_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/board_event_zone_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/guide_card_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/drag_layer_retraction_test.gd
```

Run the wider integration checks:

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/game_manager_combat_routing_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/run_flow_coordinator_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/placement_pipeline_coordinator_test.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/encounter_resolution_coordinator_test.gd
```

Run the repository search checks:

```powershell
rg -n "card\.cur_zone|board\.get_(card_cells|event_cells|cards|combat_card_chain)|card_placed" scripts scenes tests
```

Expected: no active new-flow production references remain. Legacy-only tests may mention `PersistentMarket`, but the active page must not instantiate it. Every focused and integration test passes without parser errors, invalid NodePaths, duplicate signal handling, or stale CardInstance display values.

- [ ] **Step 5: Review component documentation and commit**

Before staging, verify every new or materially refactored component in this task has the required Chinese responsibility block and that the text matches the final ownership boundary. Confirm the block names its managed responsibilities, explicit non-responsibilities, usage entry point, and direct dependencies.


```powershell
git add scripts/game_manager.gd scenes/game/game_manager.tscn scenes/game/hud/hud.tscn scripts/zone/shop.gd tests/game_manager_architecture_test.gd tests/game_manager_run_setup_test.gd tests/game_manager_event_contact_test.gd tests/game_manager_persistent_market_test.gd tests/game_page_zone_composition_test.gd tests/persistent_market_scene_test.gd tests/persistent_market_drag_test.gd
git commit -m "refactor: reassemble persistent game zones"
```

---

## Final Verification Checklist

- [ ] `Card.cur_zone` is deleted and all new-flow code reads `card.get_card_inst().cur_zone`.
- [ ] `CardInstance.ZONE.SHOP` exists and `ZONE.DRAGLAYER` does not.
- [ ] `Card.bind_card_inst()` refreshes points, armor, and artwork immediately.
- [ ] Hand, Shop, Board, and Reclaim each implement the intended `owns_card()` semantics.
- [ ] DraggerLayer caches one source before target commit and never re-reads source ownership afterward.
- [ ] Target commit precedes source commit, including same-zone drags.
- [ ] GUIDE placement returns through the single page-level `Board.card_return_requested` handler.
- [ ] BoardZone emits structured placement and chain-detach operations and has no HandZone dependency.
- [ ] BoardEventZone owns all event-grid indexing and preserves failure atomicity.
- [ ] Board exposes business signals and event entry points but no spatial proxy methods.
- [ ] `BoardPlacementResult` and `ChainRetractionTransaction` contain Card values, not CardEntity values.
- [ ] RunCardService creates one Card view per exact CardInstance and refreshes after instance mutation.
- [ ] Shop and Reclaim are resident on the active page.
- [ ] The active page has one DraggerLayer and one return-to-hand signal handler.
- [ ] No user-owned pre-existing modifications were staged by the implementation commits.

## Plan Self-Review

### Spec coverage

- Card/CardInstance ownership, display refresh, and SHOP state: Task 1.
- CardZone ownership and Hand transfer rules: Task 2.
- DraggerLayer source cache and target-first atomic protocol: Task 3.
- Shop purchase/restock and Reclaim semantics: Task 4.
- Structured BoardZone DTOs and public Card DTO migration: Task 5.
- BoardZone placement, GUIDE, cancellation, and chain detach: Task 6.
- BoardEventZone extraction and event failure atomicity: Task 7.
- Board coordinator signals and scene composition: Task 8.
- Spatial consumer and RunCardService migration: Task 9.
- Active page composition and integration regression: Task 10.

### Required prohibitions checked

- No `finalize_drag_target()` is introduced.
- No deferred or rollback drag protocol is introduced.
- BoardZone does not call HandZone.
- Board does not register with DraggerLayer.
- `card_placed` is removed rather than renamed into a second public signal.
- Shop pricing and Reclaim reward rules remain existing behavior.
- GUIDE does not create a chain-retraction transaction.

### Placeholder and type consistency checks

- Every task names exact files, interfaces, failing tests, commands, implementation behavior, passing tests, component documentation review, and commit commands.
- Every component task explicitly requires the Chinese responsibility block to be written or updated together with the implementation.
- DTO names and property types are consistent across Tasks 5, 6, 8, and 9.
- `Card` is the public view type; `CardInstance` is the persistent state type; `BoardEvent` and `EventInstance` remain event types.
- The plan contains no unresolved placeholder instructions.
