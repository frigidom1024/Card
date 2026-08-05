# Persistent Market Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent three-offer market below the Pilgrim HUD that buys cards through drag-to-hand, reclaims owned cards for gold, and shares an extensible price service with the event shop.

**Architecture:** `CardData.value` becomes the authored base value. Pure market state, pricing, and resolver classes own offer generation and economy validation; `PersistentMarket` owns UI, preview cards, feedback, and drop-target hit testing. `GameManager` coordinates player gold, card creation, hand insertion, and scene wiring, while `DragLayer` delegates market drops before its existing board-or-return behavior.

**Tech Stack:** Godot 4.7, GDScript, `.tscn` scenes, `.tres` resources, existing headless SceneTree tests.

## Global Constraints

- Keep `PersistentMarket` under `GameplayCanvas`; never assign its root `position` in code. Its Inspector position in `scenes/game/game_manager.tscn` is authoritative.
- Keep the navy-black, bone-stone, parchment, muted old-gold visual language; do not add external art assets.
- Reuse existing `CardEntity` hover information and right-click zoom for market previews.
- Market offers are preview/drag-source cards only: no board placement, rotation, reclaim, or player ownership before a successful purchase.
- Canonical base price is `CardData.value`, clamped to at least `1`; remove `ShopItemData.price`.
- Initial economy: buy `value`, reclaim `max(1, floor(value * 0.5))`, refresh `1` gold.
- Do not create a branch or commit unless the user explicitly asks.
- Run focused Godot tests using `D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe --headless --path . --script <test-file>`.

---

## File Structure

- Create `scripts/game/market/market_price_context.gd`: future-facing context object for price modifiers.
- Create `scripts/game/market/market_pricing_service.gd`: authoritative economy formulas.
- Create `scripts/game/market/persistent_market_state.gd`: run-scoped offer pool, deterministic rerolls, slot replacement.
- Create `scripts/game/market/persistent_market_resolver.gd`: validation and transaction mutations.
- Create `scripts/game/market/persistent_market.gd` and `scenes/game/persistent_market.tscn`: market presentation and drag targets.
- Create focused price, state, resolver, scene, drag, and game-manager tests under `tests/`.
- Modify `scripts/card/card_data.gd`, card `.tres` resources, event-shop scripts/resources/tests, `scripts/card/card_entity.gd`, `scripts/game/drag_layer.gd`, `scripts/game/pilgrim_crest_hud.gd`, `scenes/game/pilgrim_crest_hud.tscn`, `scripts/game_manager.gd`, and `scenes/game/game_manager.tscn`.

## Interfaces

```gdscript
class_name MarketPriceContext
extends RefCounted
var player: PlayerData
var market_state: PersistentMarketState

class_name MarketPricingService
extends RefCounted
func get_purchase_price(card_data: CardData, context: MarketPriceContext) -> int
func get_reclaim_price(card_data: CardData, context: MarketPriceContext) -> int
func get_refresh_cost(context: MarketPriceContext) -> int

class_name PersistentMarketState
extends RefCounted
const OFFER_SLOT_COUNT := 3
var offers: Array[CardData] = []
func initialize(card_library: CardLibrary, rng: RandomNumberGenerator) -> void
func get_offer(slot_index: int) -> CardData
func replace_offer(slot_index: int) -> CardData
func refresh_offers() -> void

class_name PersistentMarketResolver
extends RefCounted
enum Failure { NONE, INVALID_OFFER, HAND_FULL, INSUFFICIENT_GOLD, INVALID_CARD }
func purchase(state: PersistentMarketState, slot_index: int, player: PlayerData, hand_has_capacity: bool, context: MarketPriceContext) -> TransactionResult
func reclaim(card_data: CardData, player: PlayerData, context: MarketPriceContext) -> TransactionResult
func refresh(state: PersistentMarketState, player: PlayerData, context: MarketPriceContext) -> TransactionResult
```

### Task 1: Card Values and Price Service

**Files:** Create `scripts/game/market/market_price_context.gd`, `scripts/game/market/market_pricing_service.gd`, `tests/market_pricing_service_test.gd`; modify `scripts/card/card_data.gd:25-43` and gameplay card `.tres` resources.

**Produces:** `CardData.value`, `MarketPriceContext`, and `MarketPricingService` for both shop systems.

- [ ] **Step 1: Write the failing price test**

```gdscript
func _test_prices_use_card_value_and_never_return_zero() -> void:
    var card := CardData.new()
    card.value = 7
    var service := MarketPricingService.new()
    var context := MarketPriceContext.new()
    _expect(service.get_purchase_price(card, context) == 7, "purchase uses value")
    _expect(service.get_reclaim_price(card, context) == 3, "reclaim floors half")
    _expect(service.get_refresh_cost(context) == 1, "refresh costs one")
    card.value = 0
    _expect(service.get_purchase_price(card, context) == 1, "purchase clamps")
    _expect(service.get_reclaim_price(card, context) == 1, "reclaim clamps")
```

- [ ] **Step 2: Run it and verify it fails**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\market_pricing_service_test.gd
```

Expected: preload failure because the pricing classes do not yet exist.

- [ ] **Step 3: Implement minimum pricing API**

```gdscript
# CardData
@export_range(1, 999, 1) var value: int = 1

# MarketPricingService
func get_purchase_price(card_data: CardData, _context: MarketPriceContext) -> int:
    return maxi(1, card_data.value if card_data != null else 1)

func get_reclaim_price(card_data: CardData, context: MarketPriceContext) -> int:
    return maxi(1, get_purchase_price(card_data, context) / 2)

func get_refresh_cost(_context: MarketPriceContext) -> int:
    return 1
```

Author values in card resources using common `6`, rare `10`, epic `16`, legendary `24`, while preserving any deliberately authored user value.

- [ ] **Step 4: Run focused regressions**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\market_pricing_service_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\ribwood_card_data_test.gd
```

Expected: both exit `0`.

- [ ] **Step 5: Inspect without committing**

```powershell
git diff -- scripts/card/card_data.gd scripts/game/market/market_price_context.gd scripts/game/market/market_pricing_service.gd data/cards data/levels/ribwood/cards tests/market_pricing_service_test.gd
```

### Task 2: Run-Scoped Market State and Resolver

**Files:** Create `scripts/game/market/persistent_market_state.gd`, `scripts/game/market/persistent_market_resolver.gd`, `tests/persistent_market_state_test.gd`, `tests/persistent_market_resolver_test.gd`.

**Produces:** eligible offer selection plus atomic purchase, reclaim, and refresh results.

- [ ] **Step 1: Write failing state/resolver tests**

```gdscript
func _test_state_fills_three_non_root_offers_without_duplicates() -> void:
    var library := _library_with_cards([_card("Root", CardData.CardType.ROOT), _card("A"), _card("B"), _card("C"), _card("D")])
    var rng := RandomNumberGenerator.new()
    rng.seed = 42
    var state := PersistentMarketState.new()
    state.initialize(library, rng)
    _expect(state.offers.size() == 3, "fills three slots")
    _expect(state.offers.all(func(card): return card.card_type != CardData.CardType.ROOT), "excludes roots")
    _expect(_unique_count(state.offers) == 3, "avoids duplicates")

func _test_purchase_replaces_only_the_bought_slot() -> void:
    var result := resolver.purchase(state, 1, player, true, context)
    _expect(result.success, "purchase succeeds")
    _expect(player.gold == 23, "deducts displayed price")
    _expect(state.get_offer(0) == before_left and state.get_offer(2) == before_right, "leaves other slots")
```

- [ ] **Step 2: Run the tests and verify they fail**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\persistent_market_state_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\persistent_market_resolver_test.gd
```

- [ ] **Step 3: Implement offer state and atomic transactions**

```gdscript
func initialize(card_library: CardLibrary, source_rng: RandomNumberGenerator) -> void:
    _rng = source_rng
    _eligible_cards = card_library.cards.filter(func(card): return card != null and card.card_type != CardData.CardType.ROOT)
    refresh_offers()

func purchase(state: PersistentMarketState, slot_index: int, player: PlayerData, hand_has_capacity: bool, context: MarketPriceContext) -> TransactionResult:
    var card_data := state.get_offer(slot_index)
    if card_data == null:
        return _failure(Failure.INVALID_OFFER)
    if not hand_has_capacity:
        return _failure(Failure.HAND_FULL)
    var price := _pricing.get_purchase_price(card_data, context)
    if player.gold < price:
        return _failure(Failure.INSUFFICIENT_GOLD)
    player.gold -= price
    state.replace_offer(slot_index)
    return _success(card_data, -price)
```

Failed transactions cannot mutate gold or offers. Refresh validates first then replaces all offers. Reclaim rejects null data and credits the centralized payout.

- [ ] **Step 4: Run focused state/resolver tests**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\persistent_market_state_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\persistent_market_resolver_test.gd
```

Expected: both exit `0`.

- [ ] **Step 5: Inspect without committing**

```powershell
git diff -- scripts/game/market/persistent_market_state.gd scripts/game/market/persistent_market_resolver.gd tests/persistent_market_state_test.gd tests/persistent_market_resolver_test.gd
```
### Task 3: Gold HUD and Persistent Market Scene

**Files:** Create `scenes/game/persistent_market.tscn`, `scripts/game/market/persistent_market.gd`, `tests/persistent_market_scene_test.gd`; modify `scenes/game/pilgrim_crest_hud.tscn`, `scripts/game/pilgrim_crest_hud.gd`, and `tests/pilgrim_crest_hud_test.gd`.

**Produces:** a scene-driven market that emits intent only, plus `PilgrimCrestHud.set_gold(current_gold)`.

- [ ] **Step 1: Write failing HUD/scene tests**

```gdscript
func _test_gold_row_formats_current_gold() -> void:
    var hud := PilgrimCrestHudScene.instantiate() as PilgrimCrestHud
    root.add_child(hud)
    hud.set_gold(17)
    _expect((hud.get_node("GoldSeal/GoldValue") as Label).text == "GOLD · 17", "gold row displays current gold")

func _test_market_previews_support_info_and_zoom_but_not_rotation() -> void:
    var market := PersistentMarketScene.instantiate() as PersistentMarket
    root.add_child(market)
    market.configure(_state_with_three_cards(), _player_with_gold(30), MarketPricingService.new())
    var preview := market.get_node("OfferRow/OfferSlot1/CardPreview") as CardEntity
    _expect(preview.input_pickable, "preview receives pointer input")
    _expect(not preview.rotate_while_dragging(), "preview never rotates like a player card")
    # Emit hover/right-click through CardView and assert CardInfoOverlay plus _zoom_overlay exist.
```

- [ ] **Step 2: Run tests and verify failure**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\pilgrim_crest_hud_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\persistent_market_scene_test.gd
```

Expected: `set_gold` and the market scene are missing.

- [ ] **Step 3: Build the themed scene and controller**

```gdscript
# PilgrimCrestHud
func set_gold(current_gold: int) -> void:
    _gold_value.text = "GOLD · %d" % maxi(0, current_gold)

# PersistentMarket
func refresh_view() -> void:
    for slot_index in range(PersistentMarketState.OFFER_SLOT_COUNT):
        var preview := _offer_preview(slot_index)
        var card_data := _state.get_offer(slot_index)
        preview.bind_instance(CardInstance.new(card_data))
        preview.set_market_offer_mode(slot_index)
        (_price_label(slot_index) as Label).text = "%d GOLD" % _pricing.get_purchase_price(card_data, _context())
    _refresh_button.disabled = _player.gold < _pricing.get_refresh_cost(_context())
    _refresh_cost_label.text = "%d GOLD" % _pricing.get_refresh_cost(_context())
```

Create this hierarchy and leave its root transform Inspector-owned:

```text
PersistentMarket
  Panel / HeaderRow / TitleLabel("MARKET") / RefreshButton("REFRESH") / RefreshCostLabel
  OfferRow / OfferSlot1..OfferSlot3 / CardPreview(CardEntity) / PriceLabel
  ReclaimArea / ReclaimTitle("RECLAIM") / ReclaimHintLabel
  FeedbackLabel
```

Use `StyleBoxFlat` overrides: dark navy panel, bone-gray inset borders, parchment text, muted old-gold for buttons/highlights. `is_over_reclaim_target(global_position)` reads `ReclaimArea.get_global_rect()`. During an eligible player-card drag it displays `RECLAIM · +<payout> GOLD`; otherwise show `RECLAIM`.

- [ ] **Step 4: Run focused UI tests**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\pilgrim_crest_hud_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\persistent_market_scene_test.gd
```

Expected: both exit `0`, including three previews, refresh cost text, reclaim highlighting, hover information, and zoom.

- [ ] **Step 5: Inspect without committing**

```powershell
git diff -- scenes/game/persistent_market.tscn scripts/game/market/persistent_market.gd scenes/game/pilgrim_crest_hud.tscn scripts/game/pilgrim_crest_hud.gd tests/persistent_market_scene_test.gd tests/pilgrim_crest_hud_test.gd
```

### Task 4: Explicit Market Offer Drag Mode

**Files:** Modify `scripts/card/card_entity.gd:53-105,315-425` and `scripts/game/drag_layer.gd:7-123,213-231`; create `tests/persistent_market_drag_test.gd`.

**Produces:** market offer cards that hover/zoom and drag toward hand, but cannot preview/place on board, rotate, be reclaimed, or turn into player cards before purchase.

- [ ] **Step 1: Write failing interaction tests**

```gdscript
func _test_market_offer_drag_never_previews_or_places_on_board() -> void:
    var offer := _market_offer_card()
    drag_layer.on_card_drag_start(offer)
    offer.global_position = board.global_position + Vector2(20, 20)
    await process_frame
    _expect(not board.has_preview(), "market offer does not create board preview")
    drag_layer.on_card_drag_end(offer)
    _expect(offer.get_parent() == market.offer_container, "invalid offer drop returns to slot")

func _test_right_click_during_offer_drag_does_not_rotate() -> void:
    var rotation_before := offer.rotation_degrees
    drag_layer.on_card_drag_start(offer)
    _expect(not offer.rotate_while_dragging(), "market offer refuses rotation")
    _expect(offer.rotation_degrees == rotation_before, "preview rotation is retained")
```

- [ ] **Step 2: Run the test and verify failure**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\persistent_market_drag_test.gd
```

Expected: offer role and market-aware drops are missing.

- [ ] **Step 3: Implement a clear interaction role and drag branches**

```gdscript
# CardEntity
class_name CardEntity
extends Area2D

enum InteractionRole { PLAYER_CARD, DISPLAY_PREVIEW, MARKET_OFFER }
var interaction_role := InteractionRole.PLAYER_CARD
var market_offer_slot_index := -1

func set_market_offer_mode(slot_index: int) -> void:
    interaction_role = InteractionRole.MARKET_OFFER
    market_offer_slot_index = slot_index
    _display_info_enabled = true
    _display_zoom_enabled = true
    input_pickable = true
    _configure_card_view_pointer_input()

func can_rotate_while_dragging() -> bool:
    return interaction_role == InteractionRole.PLAYER_CARD
```

```gdscript
# DragLayer: evaluate these branches before board placement.
if card.is_market_offer():
    if market != null and market.is_over_hand_purchase_target(pos):
        market.purchase_drop_requested.emit(card.market_offer_slot_index)
    else:
        market.restore_offer_drag(card)
    return

if market != null and market.is_over_reclaim_target(pos):
    market.reclaim_drop_requested.emit(card)
    return

# Existing board placement then hand-return code remains unchanged.
```

Only call `board.preview_card()` and `_is_over_board()` for player-owned cards. Preserve parent/transform separately for market offers, board cards, and hand cards.

- [ ] **Step 4: Run interaction regressions**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\persistent_market_drag_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\card_entity_display_mode_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\board_direction_test.gd
```

Expected: all exit `0`; player-card rotation behavior is unchanged.

- [ ] **Step 5: Inspect without committing**

```powershell
git diff -- scripts/card/card_entity.gd scripts/game/drag_layer.gd tests/persistent_market_drag_test.gd
```
### Task 5: GameManager Coordination and End-to-End Flows

**Files:** Modify `scripts/game_manager.gd:12-101,108-190`, `scenes/game/game_manager.tscn:3-57`, and `tests/game_manager_player_hud_test.gd`; create `tests/game_manager_persistent_market_test.gd`.

**Produces:** persistent market initialization, synchronized HUD gold, drag-to-buy card ownership, reclaim payouts, and Inspector-controlled panel placement.

- [ ] **Step 1: Write failing manager integration tests**

```gdscript
func _test_manager_initializes_market_and_gold_hud() -> void:
    var manager := await _make_game_manager()
    var market := manager.get_node("GameplayCanvas/PersistentMarket") as PersistentMarket
    var hud := manager.get_node("GameplayCanvas/PilgrimCrestHud") as PilgrimCrestHud
    _expect(market != null, "manager owns persistent market")
    _expect(market.get_offer_count() == 3, "manager fills three offers")
    _expect((hud.get_node("GoldSeal/GoldValue") as Label).text == "GOLD · %d" % manager.player_data.gold, "HUD syncs gold")

func _test_purchase_creates_hand_card_and_reclaim_returns_gold() -> void:
    var gold_before := manager.player_data.gold
    var offered := market.get_offer_data(0)
    market.purchase_drop_requested.emit(0)
    await process_frame
    _expect(manager.hand_area.get_card_count() == hand_before + 1, "purchase inserts card")
    _expect(manager.player_data.gold == gold_before - offered.value, "purchase deducts price")
    var purchased := manager.hand_area.cards.back()
    market.reclaim_drop_requested.emit(purchased)
    await process_frame
    _expect(manager.player_data.gold == gold_before - offered.value + maxi(1, offered.value / 2), "reclaim credits half")
```

- [ ] **Step 2: Run tests and verify failure**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\game_manager_persistent_market_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\game_manager_player_hud_test.gd
```

Expected: no `PersistentMarket` scene node and no HUD gold row.

- [ ] **Step 3: Wire state, intents, and card ownership**

```gdscript
@onready var persistent_market: PersistentMarket = $GameplayCanvas/PersistentMarket
var _market_state := PersistentMarketState.new()
var _market_pricing := MarketPricingService.new()
var _market_resolver := PersistentMarketResolver.new(_market_pricing)
var _market_rng := RandomNumberGenerator.new()

func _initialize_persistent_market() -> void:
    _market_rng.randomize()
    _market_state.initialize(card_manager.card_lib, _market_rng)
    persistent_market.configure(_market_state, player_data, _market_pricing)
    persistent_market.purchase_drop_requested.connect(_on_market_purchase_drop_requested)
    persistent_market.reclaim_drop_requested.connect(_on_market_reclaim_drop_requested)
    drag_layer.market = persistent_market

func _sync_pilgrim_crest() -> void:
    pilgrim_crest_hud.set_vitality(player_stats.hp, player_stats.max_hp)
    pilgrim_crest_hud.set_faith(_faith_service.get_current_faith())
    pilgrim_crest_hud.set_gold(player_data.gold)
```

On a successful purchase, create `CardInstance.new(result.card_data)`, use `card_manager.create_card_entity`, assign `drag_layer`, restore the player-card interaction role, then call `hand_area.add_card(entity)`. If hand insertion unexpectedly fails after resolver validation, restore gold and offer state before showing `HAND FULL`. On reclaim, remove only an owned card from `HandArea`, free it after a successful resolver result, then refresh the panel/HUD. Never reclaim `CardEntity` offers.

Add the external `PersistentMarket` scene below `PilgrimCrestHud` under `GameplayCanvas` in the `.tscn`; do not set its `position` in `PersistentMarket.gd` or `GameManager._center_layout()`.

- [ ] **Step 4: Run integration/layout regressions**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\game_manager_persistent_market_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\game_manager_player_hud_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\gameplay_canvas_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\responsive_layout_scene_test.gd
```

Expected: all exit `0`; scene-controlled placement remains intact at runtime.

- [ ] **Step 5: Inspect without committing**

```powershell
git diff -- scripts/game_manager.gd scenes/game/game_manager.tscn tests/game_manager_player_hud_test.gd tests/game_manager_persistent_market_test.gd
```

### Task 6: Event-Shop Price Migration and Full Regression

**Files:** Modify `scripts/game/event/shop/shop_item_data.gd`, `scripts/game/event/shop/shop_event_resolver.gd`, `scripts/game/event/shop/shop_event_view.gd`, `data/event/content/event_shop_content.tres`, and `tests/event_runtime_test.gd`; only modify `tests/shop_card_info_test.gd` if its price assertion requires it.

**Produces:** the existing modal shop continues to work, but its price derives only from the same `MarketPricingService` as the persistent market.

- [ ] **Step 1: Change event tests to use card values and verify failure**

```gdscript
func _offer(card_name: String, value: int):
    var offer := ShopItemDataScript.new()
    offer.card_data = _card(card_name)
    offer.card_data.value = value
    return offer

func _test_shop_purchase_deducts_card_value() -> void:
    var player := PlayerDataScript.new()
    player.gold = 10
    var instance := _make_shop_instance([_offer("Twig Blade", 6)])
    var result := ShopEventResolverScript.new().purchase_item(instance, 0, player, true)
    _expect(result.success and player.gold == 4, "shop uses canonical value")
```

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\event_runtime_test.gd
```

Expected: removed legacy `ShopItemData.price` references fail until migration is complete.

- [ ] **Step 2: Route resolver and view through the price service**

```gdscript
# ShopEventResolver
var _pricing := MarketPricingService.new()

func purchase_item(instance: EventInstance, item_index: int, player: PlayerData, hand_has_capacity: bool) -> EventResolutionResult:
    # Preserve existing guard clauses, then:
    var context := MarketPriceContext.new()
    context.player = player
    var price := _pricing.get_purchase_price(item.card_data, context)
    if player.gold < price:
        return EventResolutionResult.rejected(EventResolutionResult.Failure.INSUFFICIENT_GOLD)
    player.gold -= price

# ShopEventView
price_label.text = "%d  GOLD" % _pricing.get_purchase_price(item.card_data, _price_context())
```

Remove `price` from `ShopItemData` and serialized event-shop resource items. Preserve `sold_flags`, close flow, card hover information, and right-click zoom.

- [ ] **Step 3: Run full relevant regression suite**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\event_runtime_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\shop_card_info_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\game_manager_run_setup_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\game_manager_combat_routing_test.gd
```

Expected: all exit `0`.

- [ ] **Step 4: Static verification and final diff review without committing**

```powershell
rg -n "\.price|price =" scripts/game/event/shop data/event/content/event_shop_content.tres tests/event_runtime_test.gd
git diff --check
git status --short
```

Expected: `rg` finds no `ShopItemData.price` use; `git diff --check` reports no whitespace errors; pre-existing user modifications remain untouched.

## Self-Review

### Spec Coverage

- Three persistent offers, root exclusion, duplicate behavior, replace-one purchase, and reroll-all refresh: Task 2.
- Drag-to-hand purchase and dragged owned-card reclaim: Tasks 4 and 5.
- Gold HUD, themed UI, refresh cost, and reclaim payout feedback: Task 3.
- Inspector-owned market placement: global constraints and Task 5.
- Canonical `CardData.value` and event-shop migration: Tasks 1 and 6.

### Placeholder Scan

No task uses `TODO`, `TBD`, or deferred implementation wording. Each task has owned files, concrete assertions, required implementation behavior, commands, and expected outcomes.

### Type Consistency

`MarketPricingService` accepts `CardData` plus `MarketPriceContext` in both shop systems. `PersistentMarketState` owns `Array[CardData]` offers; `PersistentMarketResolver` owns their economy mutation. `PersistentMarket` emits UI intent, while `GameManager` owns `CardEntity` creation/destruction and `HandArea` mutation.