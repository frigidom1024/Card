# Persistent Market Design

## Goal

Replace the one-off shop-event economy with a persistent market on the gameplay screen. The market lives below the Pilgrim HUD, offers three cards at all times, supports drag-to-buy into the hand area, and lets the player reclaim owned cards for gold.

## Scope

- Add a persistent right-side market panel to `GameManager`.
- Display three purchasable card offers.
- Buy by dragging a market card into the hand area.
- Refresh all offers for a gold cost.
- Reclaim a player-owned card by dragging it into the reclaim area.
- Add gold to the Pilgrim HUD and keep it synchronized with `PlayerData.gold`.
- Move the base card price to `CardData`.
- Centralize purchase, reclaim, and refresh price calculation behind a market-pricing API.
- Migrate the existing event shop to use the same price API.

## Non-goals

- New ways to earn gold beyond the existing `PlayerData.gold` sources.
- Map-specific market pools, rarity weighting, discounts, relic modifiers, or curse modifiers.
- Selling cards directly from an unresolved event modal.
- Changing Faith mechanics.

## UI Layout

The fixed-design gameplay scene owns the layout. The `PersistentMarket` scene is placed below `GameplayCanvas/PilgrimCrestHud` in `game_manager.tscn`; its root scene position remains editable in the Godot Inspector.

```
Pilgrim HUD
  - VITALITY
  - GOLD
  - FAITH

Persistent Market
  - Header: MARKET
  - Offer area
      - Refresh button: REFRESH
      - Refresh cost label: 1 GOLD
      - Three offer slots
  - Reclaim area
      - RECLAIM
      - Dynamic payout hint while an owned card is dragged over it
```

The panel uses the same navy-black, bone-stone, parchment, and muted old-gold language as the Pilgrim HUD. The offer cards are intentionally smaller than hand cards but remain large enough to support existing hover detail and right-click zoom interactions.

## Data and Pricing

### Card base value

`CardData` gains an inspector-editable `value: int` field. It is the canonical base value for that card and must be at least 1.

`ShopItemData.price` is removed. A shop item determines which card is offered, not how the card is priced.

### Pricing service

`MarketPricingService` owns all economy formulas. Its public API takes a card and a context object so future relics, curses, map rules, and discounts can change prices without changing drag, UI, or resolver code.

```gdscript
func get_purchase_price(card_data: CardData, context: MarketPriceContext) -> int
func get_reclaim_price(card_data: CardData, context: MarketPriceContext) -> int
func get_refresh_cost(context: MarketPriceContext) -> int
```

Initial formulas:

- Purchase: `card_data.value`
- Reclaim: `max(1, floor(card_data.value * 0.5))`
- Refresh: `1 GOLD`

The initial `MarketPriceContext` contains only the player and market state required by the service. It provides an explicit extension point without prematurely adding modifiers.

## Persistent Market State

`PersistentMarketState` exists for a single run and owns:

- Three current offer card-data references.
- The market draw source and RNG state.
- The next refresh state, if modifiers are added later.

On run initialization, the state fills all three slots from the current `CardLib`. A successful purchase immediately replaces only the purchased slot. A successful refresh replaces all three slots. The first implementation samples without duplicate cards when the eligible pool has at least three entries; otherwise duplicates are allowed.

## Interactions

### Drag-to-buy

1. The player begins dragging an offer card.
2. The card becomes a temporary drag preview and never joins the player deck before validation.
3. On release over `HandManager`, the market validates hand capacity and gold using `MarketPricingService`.
4. On success, it deducts gold, creates a new `CardInstance`, inserts it through `HandArea.add_card`, replaces the offer slot, and updates the HUD and market.
5. On failure, the drag preview returns to its offer slot and the market shows either `NOT ENOUGH GOLD` or `HAND FULL`.

Market offer cards cannot be placed on the board, rotated as gameplay cards, reclaimed, or retracted from the card chain.

### Refresh

The refresh button calls the pricing service for its displayed cost. If the player can pay, it subtracts gold and rerolls all three offers. If not, the button is disabled and the market shows the required cost.

### Reclaim

1. The player starts dragging an owned hand card or a board card that has been retracted through the existing drag flow.
2. While the card overlaps `ReclaimArea`, the area highlights and displays the payout from `get_reclaim_price`.
3. On release, the market removes the card from its owning area, destroys it, adds the payout to `PlayerData.gold`, and updates the HUD.
4. A rejected reclaim returns the card to its original legal state. Market offer cards can never be reclaimed.

## Integration Boundaries

- `DragLayer` remains responsible for drag ownership and restores cards on failed drops. It delegates drop-target decisions to the board, hand area, and persistent market.
- `PersistentMarket` owns presentation and emits requests; `GameManager` owns player-data mutation and card instance creation.
- `MarketPricingService` is the sole source for displayed and resolved prices.
- `PilgrimCrestHud` displays Gold, Faith, and Vitality but does not calculate any values.
- The existing event-shop resolver delegates its price calculation to `MarketPricingService` after migration.

## Error and Edge Cases

- A full hand rejects purchases without charging gold.
- Insufficient gold rejects purchase or refresh without changing offers.
- Reclaiming the final card in a hand is allowed.
- A card dragged from the board follows the existing chain-retraction rules before it can be reclaimed.
- Market drag previews never trigger board hover previews or event flips.
- Offer slot replacement only occurs after a successful purchase.
- All visible prices refresh after gold-affecting modifiers are added in later work.

## Acceptance Criteria

- The game screen shows a persistent market below the Pilgrim HUD.
- The market always contains three offer slots.
- The HUD visibly updates `GOLD` after buying, refreshing, and reclaiming.
- Dragging a market card into a non-full hand buys it at `CardData.value`.
- Dragging an owned card into the reclaim area grants half its value, minimum 1.
- Refreshing costs the value returned by `MarketPricingService` and rerolls all offers.
- Insufficient gold and full-hand failures leave cards, offers, and gold unchanged.
- Existing event-shop prices use the same market-pricing API.
- Market and reclaim areas remain editable as scene nodes in the Godot Inspector.