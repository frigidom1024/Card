# STACK//STRIKE Brand Name Design

**Date:** 2026-08-10  
**Status:** Approved — user confirmed implementation and the STACK//STRIKE rename is complete.

## Goal

Replace the player-facing title `MonoCard` with `STACK//STRIKE` so the game identity matches its pixel-arcade card-table direction and its core loop: build a card chain, compare card strength against encounters, earn coins, and improve the deck.

## Naming Decision

- **Official display name:** `STACK//STRIKE`
- **Tagline:** `BUILD A DECK. BREAK THE BOARD.`
- **Pronunciation / reading:** “Stack Strike”; the double slash is a visual separator, not a command or path.

`STACK` represents placing and extending a card chain. `STRIKE` represents resolving that chain against enemies. The name does not depend on the retired bone, pilgrimage, or deity visual motifs.

## Scope

### Included

1. Update Godot application display name in `project.godot` to `STACK//STRIKE`.
2. Replace player-facing `MonoCard` / `MONOCARD` title text in the active main-menu scene with `STACK//STRIKE`.
3. Update only title-level menu copy required to keep the header coherent with the new name and tagline.
4. Preserve scene paths, script class names, resource identifiers, save keys, and repository folder name `mono-card`; these are implementation details and are not renamed in this change.

### Excluded

- Main-menu layout, palette, animations, and pixel-art treatment.
- Game mechanics, cards, combat, events, localization infrastructure, and asset generation.
- Renaming historical documentation, git branches, previous commits, or inactive worktrees.

The larger `NEON DECK LOBBY` menu redesign remains a separate approved-design and implementation task; this specification only makes its branding target unambiguous.

## Menu Copy

The menu header will use:

```text
STACK//STRIKE
BUILD A DECK. BREAK THE BOARD.
```

If available space is too narrow at a supported resolution, the name may wrap only at the slash boundary:

```text
STACK//
STRIKE
```

It must not truncate, scale below the existing minimum readable title size, or substitute a single slash.

## Technical Constraints

- The value in `[application] config/name` must match the official display name exactly: `STACK//STRIKE`.
- Existing gameplay references to `MonoCard` that are not player-facing titles are not modified without a separate migration plan.
- The change must not alter `run/main_scene`, autoload registration, or resource paths.
- Existing home-screen flow must continue to open the same scenes and actions after the copy replacement.

## Verification

1. `project.godot` reports `config/name="STACK//STRIKE"`.
2. Launching the project displays `STACK//STRIKE` in the window title / application identity where Godot exposes it.
3. The active main-menu header displays the exact title and tagline above.
4. Existing main-menu and home-screen tests pass, except for clearly documented pre-existing failures unrelated to this copy change.
5. A grep for player-facing main-menu `MonoCard` / `MONOCARD` finds no remaining active title copy.
