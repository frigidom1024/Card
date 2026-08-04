# Card Paper Depth Design

**Date:** August 3, 2026
**Status:** Revised — awaiting user review

## Goal

Give every in-game card a restrained paper-card presence with only a hint of thickness, without adding PNG frame assets or obscuring low-detail card illustrations.

## Scope

- Extend the existing procedural Godot card-frame scenes only.
- Keep `COMMON`, `RARE`, `EPIC`, and `LEGENDARY` frame scenes independently editable.
- Preserve the existing rarity-color system, numeric combat tags, card dimensions, and rotation behavior.
- Do not add textures, shaders, glow, or external art resources.

## Visual Construction

Each rarity-frame scene gains the same three depth layers behind its existing borders:

1. **Soft Shadow** — a translucent charcoal panel offset 1 px right and 2 px down. It rotates with the card and gives the card a barely raised presence above the board.
2. **Paper Core** — a dark warm-brown paper edge offset 1 px right and 1 px down. It suggests a compressed paper stack without reading as a thick object.
3. **Paper Face Inset** — a low-contrast warm-gray inner edge on the front face. The top and left edges are faintly lighter; the bottom and right edges remain darker through the paper core and shadow.

The existing outer border, inner border, and top accent remain above these layers. Rarity colors continue to appear only in the existing front-frame border and accent.

## Scene Structure

Every file under `scenes/card_view/frames/` will use this node order:

```text
CardFrame
├── SoftShadow
├── PaperCore
├── OuterBorder
├── InnerBorder
└── HeaderAccent
```

All depth values live in editable `StyleBoxFlat` subresources within each `.tscn`. No runtime script changes are required.

## Constraints

- Depth must remain nearly flat at gameplay scale: shadow alpha below 0.25 and paper-core offset no more than 1 px horizontally or vertically.
- The right/bottom paper edge must not collide with the combat-tag bar beneath the card.
- No high-key white paper, glossy gradients, glowing edges, bevel textures, or metallic side effects.
- Frame scenes must remain valid independently and continue to fill `FrameHost` exactly.

## Verification

- Extend `tests/card_view_visual_scene_test.gd` to assert that every rarity frame exposes `SoftShadow` and `PaperCore`.
- Run the focused visual scene test.
- Run Godot headless editor loading to validate all edited `.tscn` scenes.
- Run `git diff --check`.

## Out of Scope

- Replacing card illustrations.
- Adding per-card paper damage, animated wobble, or hover-specific lighting.
- Changing card layout, statistics, or rarity balance.