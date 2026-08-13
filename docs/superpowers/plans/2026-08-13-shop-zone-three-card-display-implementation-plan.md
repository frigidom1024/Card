# ShopZone Three-Card Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the prototype ShopZone HBoxContainer with a scripted Control that displays up to three `Card` scene instances horizontally without taking ownership of their sizes or pointer input.

**Architecture:** `ShopZone` becomes a focused `Control` (`scripts/zone/shop_zone.gd`) that tracks an ordered list of direct `Card` children. It responds to child/tree and resize changes with a deferred layout pass, calculating centered positions from each card's live size while only modifying `position`. The scene owns three default Card instances for editor preview; the script provides a small API for runtime product replacement.

**Tech Stack:** Godot 4.7, GDScript, headless Godot scene-test scripts.

## Global Constraints

- Use `res://scenes/card/card.tscn` / `Card`, not the runtime `CardEntity` shop system.
- Display no more than three product cards.
- Never modify a managed card's `size`, scale, mouse filter, GUI signal connections, or drag state while laying it out.
- Preserve `Card` pointer interaction by setting the ShopZone root to `Control.MOUSE_FILTER_IGNORE`.
- Do not add purchase, currency, or cross-zone-drag behavior.

---

### Task 1: Add the ShopZone layout regression test

**Files:**
- Create: `.tmp/shop_zone_layout_test.gd`
- Test: `.tmp/shop_zone_layout_test.gd`

**Interfaces:**
- Consumes: `res://scenes/zone/shop_zone.tscn`, current `Card` scene.
- Produces: a headless test that asserts the intended public layout/API contract.

- [ ] **Step 1: Write the failing test**

Create a `SceneTree` script that instantiates `shop_zone.tscn`, waits one frame, and asserts:

```gdscript
var zone := scene.instantiate() as ShopZone
assert(zone.mouse_filter == Control.MOUSE_FILTER_IGNORE)
assert(zone.get_products().size() == 3)
for card in zone.get_products():
    assert(card.size == Vector2(84, 154))
    assert(card.get_global_rect().size.x > 0.0)
assert(zone.get_products()[0].position.x < zone.get_products()[1].position.x)
assert(zone.get_products()[1].position.x < zone.get_products()[2].position.x)
```

Also set the zone to `Vector2(300, 200)`, await one frame, and assert card sizes are unchanged and the group is horizontally centered within a small float tolerance.

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --script res://.tmp/shop_zone_layout_test.gd
```

Expected: failure because ShopZone currently has no display API / direct card layout.

- [ ] **Step 3: Keep the test as the regression harness**

Do not change the expected contract after production implementation begins. The test remains the direct proof of the prior zero-width card regression and its fix.

---

### Task 2: Implement the focused ShopZone layout controller

**Files:**
- Create: `scripts/zone/shop_zone.gd`
- Test: `.tmp/shop_zone_layout_test.gd`

**Interfaces:**
- Consumes: `Card` instances as direct children.
- Produces:
  - `class_name ShopZone`
  - `func set_products(cards: Array[Card]) -> void`
  - `func set_product(slot_index: int, card: Card) -> void`
  - `func clear_products() -> void`
  - `func get_products() -> Array[Card]`

- [ ] **Step 1: Write minimal implementation**

Implement a `Control` with exported `max_products := 3`, `card_gap := 12.0`, and `fallback_card_size := Vector2(84, 154)`. On ready, set `mouse_filter = Control.MOUSE_FILTER_IGNORE`, collect visible direct `Card` children in scene-tree order, and schedule a deferred layout. Connect to `resized`, `child_entered_tree`, and `child_exiting_tree` to reschedule that pass.

Use the following layout formula for N cards:

```gdscript
var sizes: Array[Vector2] = products.map(func(card): return card.size if card.size.x > 0.0 and card.size.y > 0.0 else fallback_card_size)
var cards_width := sizes.reduce(func(sum, card_size): return sum + card_size.x, 0.0)
var gap := minf(card_gap, maxf(0.0, (size.x - cards_width) / maxf(float(products.size() - 1), 1.0)))
var total_width := cards_width + gap * float(products.size() - 1)
var x := (size.x - total_width) * 0.5
```

Assign each `card.position = Vector2(x, (size.y - card_size.y) * 0.5)` and advance `x` by the card width plus gap. Do not write `card.size`.

`set_products` must reject/trim products beyond `max_products`, reparent accepted cards to `ShopZone` with global transform preservation, hide unselected existing direct Card children, set accepted cards visible, preserve caller array ordering, and schedule layout. `set_product` replaces one logical item if index is within 0..2; invalid indices emit `push_error` and make no changes. `clear_products` hides and clears the ordered product list without freeing instances. `get_products` returns a duplicate array.

- [ ] **Step 2: Run the regression test to verify it passes**

Run the Task 1 command.

Expected: exit code 0 with every assertion passing.

- [ ] **Step 3: Test a zero-size Card fallback path**

In the headless test, instantiate a `Card` with zero `size`, pass it to `set_products([card])`, await one frame, and assert the calculated `position` uses the fallback dimensions while the card's own `size` is not changed.

- [ ] **Step 4: Run the expanded test**

Run the Task 1 command again.

Expected: exit code 0.

---

### Task 3: Rebuild the ShopZone scene with direct product cards

**Files:**
- Modify: `scenes/zone/shop_zone.tscn`
- Test: `.tmp/shop_zone_layout_test.gd`

**Interfaces:**
- Consumes: `ShopZone` script from Task 2 and `res://scenes/card/card.tscn`.
- Produces: a scene with exactly three visible direct Card children, no HBoxContainer, and `mouse_filter = 2`.

- [ ] **Step 1: Modify the scene**

Replace the old `CardZone` script dependency and `HBoxContainer` tree with an external script resource for `res://scripts/zone/shop_zone.gd` plus one external PackedScene reference for `res://scenes/card/card.tscn`. Add Card3, Card, and Card2 directly below ShopZone, each with the default 84×154 extents inherited from the card scene and visible state enabled.

Keep ShopZone's authored size at `289×163`; the controller will position the three cards with compressed gap at that narrow preview width.

- [ ] **Step 2: Run the regression test**

Run the Task 1 command.

Expected: exit code 0, three cards have positive input rect widths, and their x coordinates are ascending.

- [ ] **Step 3: Run Godot's scene load check**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64.exe' --headless --path . --editor --quit
```

Expected: exit code 0 and no scene or script parse errors printed.

---

### Task 4: Final focused verification

**Files:**
- Modify: `docs/superpowers/specs/2026-08-13-shop-zone-three-card-display-design.md` only if implementation differs from the accepted contract.
- Verify: `.tmp/shop_zone_layout_test.gd`, `scenes/zone/shop_zone.tscn`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: fresh evidence for all design acceptance criteria.

- [ ] **Step 1: Run the headless layout/API test**

Run the Task 1 command and inspect its exit code/output.

- [ ] **Step 2: Re-read acceptance criteria**

Check all six criteria in `docs/superpowers/specs/2026-08-13-shop-zone-three-card-display-design.md` against the fresh test and editor-load output.

- [ ] **Step 3: Inspect the final diff**

Run:

```powershell
git diff -- scripts/zone/shop_zone.gd scenes/zone/shop_zone.tscn docs/superpowers/specs/2026-08-13-shop-zone-three-card-display-design.md docs/superpowers/plans/2026-08-13-shop-zone-three-card-display-implementation-plan.md
```

Confirm only the intended focused ShopZone implementation and process documentation changed.
