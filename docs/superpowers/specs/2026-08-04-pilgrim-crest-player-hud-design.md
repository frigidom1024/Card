# Pilgrim Crest Player HUD Design

## Goal

Replace the ad hoc faith-only gameplay readout with a compact, combat-first player information panel named **Pilgrim Crest**. The HUD must make vitality and faith immediately readable while preserving the existing dark-indigo, bone-paper, and antique-gold presentation. It must not alter card, board, combat, or input behavior.

## Scope

- Add one reusable Control-based player HUD to the gameplay design canvas.
- Show the player identity, current map label, vitality, and faith.
- Show curse and combat-status text only while an active status exists.
- Keep temporary defense out of the persistent player HUD.
- Expose visual tuning values in the Godot Inspector where practical.
- Use only native Godot controls and `StyleBoxFlat`; no new raster art assets are required.

## Information Hierarchy

1. **Vitality:** the primary permanent combat readout, displayed as `HP current / max` with a dark crimson fill bar.
2. **Faith:** the secondary persistent resource, displayed as a compact labeled seal below vitality.
3. **Identity and location:** a small sacred crest, `PILGRIM`, the player's subtitle, and `RIBWOOD` provide context without competing with combat values.
4. **Temporary status:** a single line such as `CURSE · BONE CHILL` appears only for an active curse, residual-echo enhancement, or turn-scoped combat condition.

`DEF` is deliberately excluded. Defense is a temporary zero-default combat state, so it belongs in card effects, damage resolution feedback, and momentary combat messaging rather than the player's persistent information panel.

## Visual Design

### Placement and Size

- Anchor the panel to the top-left of `GameplayCanvas` within the 1920×1080 design viewport.
- Keep a 32–48 px outer margin from the top and left design edges.
- Target a width of 250–290 px and a height of 210–250 px when no temporary status is active.
- Let the panel extend vertically only when the optional status row is visible.

### Panel Layers

1. **Outer plaque:** muted indigo-black, slightly translucent, with a restrained rounded or clipped-corner silhouette.
2. **Bone-paper inset:** a narrow gray-bone inner panel that establishes hierarchy around the vital readouts.
3. **Gold accents:** one thin antique-gold frame line, a small crest divider, and subtle corner marks; no high-brightness glow.
4. **Vitality area:** large warm bone `HP` numbers, subdued max value, and a short deep-crimson health bar with a low-contrast track.
5. **Faith seal:** a compact dark-gold badge reading `FAITH · <value>`.
6. **Status row:** muted red-gold text on a restrained dark strip. It is hidden and does not reserve space when no temporary state exists.

## Data and Update Behavior

- The HUD reads existing `GameManager` player state: `player_stats.hp`, player maximum HP, and `faith_changed` / `FaithService`.
- The map label is initially `RIBWOOD`; it is configured as display data so later maps can supply their own name without redesigning the scene.
- Combat systems supply a short display-ready temporary status string only while that condition is active. Clearing the condition hides the entire status row.
- HP and faith changes use a brief, restrained number emphasis or bar interpolation. The HUD does not introduce new game state or modify combat outcomes.

## Interaction and Rendering

- Build the HUD under the existing `GameplayCanvas` so it scales with the gameplay design viewport.
- Every decorative and text node uses `MOUSE_FILTER_IGNORE`; the HUD must not capture hover, clicks, card dragging, or right-click card inspection.
- Render the HUD above board background decoration but below modal, card-detail, hover-information, and drag-preview layers.
- Reuse `RenderPriority` or its documented layer constants only where required to make the ordering inspectable and consistent.

## Editor Configuration

The reusable HUD scene exposes Inspector-editable properties for:

- title, subtitle, and current map label;
- plaque, inset, gold trim, vitality bar, faith seal, and status colors;
- outer margin, panel width, and compact spacing;
- visibility and text of the temporary status row;
- optional crest glyph or icon text.

## Acceptance Criteria

- Normal gameplay shows one unobtrusive top-left Pilgrim Crest with player identity, `HP current / max`, a vitality bar, and faith.
- No persistent `DEF` readout appears.
- A curse or combat-status line appears only while that state is active and collapses completely when cleared.
- HP and faith update from the current runtime services without duplicating state.
- Cards, board events, hover cards, dragging, and right-click card inspection remain fully interactive beneath the panel.
- A designer can tune the principal layout and colors from the Godot Inspector without editing GDScript.
