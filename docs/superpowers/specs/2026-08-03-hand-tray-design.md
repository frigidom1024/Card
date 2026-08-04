# Hand Tray Design

## Goal

Replace the existing debug hand-area rectangle with a fixed-screen visual container that feels like a pilgrim's offering tray. The tray should support the game's dark indigo, antique-gold, and bone-paper visual language without changing card placement, dragging, hover, or combat behavior.

## Scope

- Add a reusable `HandTray` scene beneath the gameplay hand area.
- Keep the tray fixed to the design viewport's lower edge.
- Keep every decorative node mouse-transparent so card interaction remains unchanged.
- Surface the tray's main styling values in the Inspector.
- Replace the debug-only hand background with a small English hand-count label.

## Visual Design

### Placement

- Width: 76–82% of the 1920×1080 design viewport.
- Height: 210–240 px.
- The tray sits on the bottom edge with a small lower bleed, so it reads as a built-in sacred object rather than a floating panel.

### Layers

1. **Outer tray:** muted deep indigo-black, slightly more opaque near the lower edge, with a restrained small-radius silhouette.
2. **Inner lining:** a narrow, low-contrast gray-bone strip that visually gathers the hand cards without competing with their card faces.
3. **Gold trim:** one thin antique-gold line along the upper edge plus two subtle side clasps or pointed arch ornaments.
4. **Hand readout:** small muted-gold `HAND · current / max` label at the upper-left of the tray.
5. **Future slot:** an empty upper-right anchor reserved for draw, discard, or turn information; no new game function is added now.

## Interaction and Rendering

- The tray is a `Control`-based screen UI and is rendered behind the hand cards.
- All tray nodes use `MOUSE_FILTER_IGNORE` so they cannot capture hover, drag, left-click, or right-click input from a card.
- Existing `HandArea` layout remains a horizontal centered layout with the same hover scale and lift behavior.
- The tray is not responsible for card z-index ordering; `HandArea` and `RenderPriority` continue to own that behavior.

## Editor Configuration

`HandTray` exposes Inspector-editable properties for:

- tray background color and opacity;
- inner lining color and opacity;
- antique-gold trim color;
- tray height and width ratio;
- lower-edge bleed;
- side-ornament visibility;
- hand-count text style and visibility.

The scene is intentionally built from Godot native `Panel`, `ColorRect`, `StyleBoxFlat`, and `Label` nodes. No new raster art assets are required for this pass.

## Acceptance Criteria

- The old blue debug rectangle is no longer visible in normal gameplay.
- The tray is fixed at the bottom of the gameplay viewport and remains visually behind all hand cards.
- Hovering, dragging, and right-clicking a hand card work as before.
- The hand count updates when cards are added, removed, or the hand is cleared.
- A designer can adjust the tray's key visual values from the Inspector without editing code.