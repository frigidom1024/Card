# Card Artwork Path Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render optional card illustration files from `CardData.artwork_path` in every `CardView`, with a reliable no-art placeholder.

**Architecture:** `CardData` owns a designer-editable `res://` file path. The reusable `CardView` scene adds an `Artwork` TextureRect below `FrameHost`, then its script resolves the path on each display refresh. A sibling placeholder remains visible only while no usable texture is assigned.

**Tech Stack:** Godot 4.7, GDScript, `ResourceLoader`, `TextureRect`, `ColorRect`, `Label`, and existing SceneTree tests.

## Global Constraints

- Store artwork as an Inspector-selectable string path, not a `Texture2D` reference.
- Accept only PNG, WebP, JPG, and JPEG selections.
- Keep all placeholder copy in English: `UNILLUSTRATED`.
- Render artwork above the card surface and below existing rarity frames.
- Preserve existing cards with empty image paths and do not modify uncommitted Ribwood resources.
- Keep all decorative artwork controls mouse-transparent.
- Do not stage, commit, or alter unrelated working-tree files.

---

### Task 1: Cover Card Art Binding and Fallbacks

**Files:**
- Modify: `tests/card_view_visual_scene_test.gd`

**Interfaces:**
- Consumes: `CardData.artwork_path: String` and `CardView.set_value(value: CardInstance) -> void`.
- Verifies: `Artwork` receives a texture for a valid image path; `ArtworkPlaceholder` is used for empty and invalid paths.

- [ ] **Step 1: Add failing valid-image and fallback assertions**

Create `CardData` instances in the existing card-view scene test. Assign `res://assert/card/ribwood_guardian_root.png` for the valid case, then assert `Artwork.visible`, its `texture != null`, and `ArtworkPlaceholder` hidden. Set `artwork_path` to `""` and a non-existent `res://` path in separate cases, then assert the texture is cleared and the placeholder is visible.

- [ ] **Step 2: Run the focused test to verify the assertions fail**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\card_view_visual_scene_test.gd
```

Expected: failure because `CardData` has no `artwork_path` and `CardView` has no artwork nodes.

### Task 2: Add the Data Field and Artwork Presentation Layer

**Files:**
- Modify: `scripts/card/card_data.gd`
- Modify: `scenes/card_view/card_view.tscn`
- Modify: `scripts/card/card_view.gd`
- Test: `tests/card_view_visual_scene_test.gd`

**Interfaces:**
- Produces: `@export_file("*.png", "*.webp", "*.jpg", "*.jpeg") var artwork_path: String = ""` on `CardData`.
- Produces: `Artwork: TextureRect` and `ArtworkPlaceholder: Control` in `card_view.tscn`.
- Produces: `CardView._update_artwork() -> void`, called by `refresh_display()`.

- [ ] **Step 1: Add the exported data field**

Place `artwork_path` after card identity fields in `CardData`. Keep its default empty so all existing `.tres` files remain valid and show the fallback.

- [ ] **Step 2: Add artwork and placeholder controls**

Place `Artwork` after `SurfaceInset` and before `FrameHost`; use full-rect anchors, inset offsets matching the card’s safe art region, `TextureRect.STRETCH_KEEP_ASPECT_COVERED`, and ignored mouse input. Add a full-rect, ignored-input `ArtworkPlaceholder` with a dark muted background and centered `UNILLUSTRATED` label beneath `FrameHost`.

- [ ] **Step 3: Resolve the image path on refresh**

Add typed onready references to both nodes. `_update_artwork()` clears old state first, ignores empty and non-`res://` paths, uses `ResourceLoader.load(path, "Texture2D") as Texture2D`, and toggles artwork and placeholder visibility only after a valid texture is present. Call it after `_update_frame()` from `refresh_display()`.

- [ ] **Step 4: Run focused card-view presentation test**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests\card_view_visual_scene_test.gd
```

Expected: exit code 0.

### Task 3: Verify Consumers and Scene Parsing

**Files:**
- Verify only: `tests/card_entity_display_mode_test.gd`
- Verify only: `tests/card_zoom_overlay_test.gd`
- Verify only: `tests/event_ui_scene_test.gd`

- [ ] **Step 1: Run consumer-focused tests**

Run the focused card-view test plus `card_entity_display_mode_test.gd`, `card_zoom_overlay_test.gd`, and `event_ui_scene_test.gd` with the Godot console executable.

- [ ] **Step 2: Parse scenes and inspect the patch**

Run the Godot editor headless, then `git diff --check` limited to the planned files. Do not stage or commit the changes.