# Card Detail UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the basic card hover and zoom UI with the approved Field Ledger and Pilgrim's Record presentation while keeping existing card interactions intact.

**Architecture:** A small formatter class owns all English rarity, type, tag, short-description, and stat-entry formatting. A reusable `CardDetailStatSeal` scene renders the approved muted stat treatment in both `CardInfo` and `ZoomView`; `CardInfoOverlay` retains screen-space placement, while `CardEntity` retains hover and zoom lifecycle ownership.

**Tech Stack:** Godot 4.7, GDScript, `.tscn` scenes, `StyleBoxFlat`, existing BAR SADY font resource, headless `SceneTree` script tests.

## Global Constraints

- Keep all player-facing card-detail copy in English.
- Preserve hover behavior: the panel stays upright, prefers the card's right side, flips to the left when needed, clamps vertically, ignores mouse input, and hides immediately after leaving the card.
- Preserve gameplay input, display-only behavior, dragging, and left-click zoom behavior.
- Use dark ink-blue, antique-gold, bone-paper, muted brick-red, cold-steel blue, and dark teal; do not use glossy panels, bright glows, or saturated red/yellow/green stat blocks.
- Reuse `RenderPriority`; do not add raw `CanvasLayer.layer` or `z_index` numbers.
- Do not add raster art resources, alter card data, or change combat logic.
- Do not create Git commits; the user has not requested one.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `scripts/card/card_detail_format.gd` | Provides one English source of truth for card rarity, type, tag, summary, and non-zero stat data. |
| `scripts/card/card_detail_stat_seal.gd` | Maps one stat kind to approved copy, color, and panel style. |
| `scenes/card_view/card_detail_stat_seal.tscn` | Editable `PanelContainer` scene for a single detail-stat seal. |
| `scripts/card/card_info.gd` | Populates the compact Field Note from a `CardInstance`. |
| `scenes/card_view/card_info.tscn` | Declares Field Note layout and local ink-blue/old-gold styles. |
| `scripts/card/card_zoom_view.gd` | Populates the full Pilgrim's Record and instantiates its true `CardView` preview. |
| `scenes/card_view/zoom_view.tscn` | Declares the two-column Pilgrim's Record layout and close hint. |
| `scripts/card/card_entity.gd` | Keeps the existing zoom lifecycle while changing only the ZoomBg treatment if needed. |
| `tests/card_detail_ui_test.gd` | Validates the formatter and reusable detail-stat seal independently. |
| `tests/card_info_overlay_test.gd` | Extends hover coverage with Field Note data, English copy, and mouse pass-through assertions. |
| `tests/card_zoom_overlay_test.gd` | Extends zoom coverage with the record layout, card preview, layer, and close behavior assertions. |

### Task 1: Add Shared Card Detail Formatting and Stat Seals

**Files:**
- Create: `scripts/card/card_detail_format.gd`
- Create: `scripts/card/card_detail_stat_seal.gd`
- Create: `scenes/card_view/card_detail_stat_seal.tscn`
- Create: `tests/card_detail_ui_test.gd`

**Interfaces:**
- Produces `CardDetailFormat.rarity_name(rarity: CardData.Rarity) -> String`, `CardDetailFormat.card_type_name(card_type: CardData.CardType) -> String`, `CardDetailFormat.tag_name(tag: CardData.CardTag) -> String`, `CardDetailFormat.compact_description(text: String, character_limit: int = 120) -> String`, and `CardDetailFormat.stat_entries(data: CardData) -> Array[Dictionary]`.
- Produces `CardDetailStatSeal.Attribute` with `DAMAGE`, `DEFENSE`, and `HEAL`, plus `CardDetailStatSeal.configure(attribute: Attribute, value: int) -> void`.
- `stat_entries` returns dictionaries with exactly `attribute: CardDetailStatSeal.Attribute` and `value: int`, in damage, defense, heal order, and never returns zero-value entries.

- [ ] **Step 1: Write the failing formatter and seal test**

Create `tests/card_detail_ui_test.gd` as a `SceneTree` script. Preload `card_detail_stat_seal.tscn`, construct a `CardData` with `damage = 8`, `defense = 2`, and `heal = 0`, then assert the following exact contract:

```gdscript
_expect(CardDetailFormat.rarity_name(CardData.Rarity.RARE) == "RARE", "rarity uses English display copy")
_expect(CardDetailFormat.card_type_name(CardData.CardType.ROOT) == "ROOT", "root type uses English display copy")
_expect(CardDetailFormat.tag_name(CardData.CardTag.WEAPON) == "WEAPON", "tag uses English display copy")
_expect(CardDetailFormat.compact_description("abc", 2) == "a…", "long hover descriptions truncate with an ellipsis")

var entries := CardDetailFormat.stat_entries(data)
_expect(entries.size() == 2, "zero-value detail stats are omitted")
_expect(entries[0].attribute == CardDetailStatSeal.Attribute.DAMAGE and entries[0].value == 8, "damage is first")
_expect(entries[1].attribute == CardDetailStatSeal.Attribute.DEFENSE and entries[1].value == 2, "defense follows damage")
```

Instantiate one seal, call `seal.configure(CardDetailStatSeal.Attribute.DAMAGE, 8)`, and assert `ValueLabel.text == "8 STRIKE"`. Retrieve the root `panel` style box and assert its background has `r > g` and `r > b`, proving the damage seal is muted red rather than an unstyled default.

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_detail_ui_test.gd
```

Expected: non-zero exit because the formatter class and detail-stat seal scene do not exist yet.

- [ ] **Step 3: Implement `CardDetailFormat`**

Create `scripts/card/card_detail_format.gd` with `class_name CardDetailFormat` and static mapping functions. Use these exact display values:

```gdscript
const RARITY_NAMES := {
	CardData.Rarity.COMMON: "COMMON",
	CardData.Rarity.RARE: "RARE",
	CardData.Rarity.EPIC: "EPIC",
	CardData.Rarity.LEGENDARY: "LEGENDARY",
}

const CARD_TYPE_NAMES := {
	CardData.CardType.ROOT: "ROOT",
	CardData.CardType.NORMAL: "CARD",
}
```

Map every `CardData.CardTag` to the existing English name: `WEAPON`, `DEFENSE`, `HEAL`, `RESOURCE`, `LOCATION`, `CREATURE`, `ITEM`, `EVENT`, `HOLY`, `DARK`, and `NATURE`. Unknown values must return `UNKNOWN`.

Implement `compact_description` by stripping line breaks, trimming whitespace, returning the full text when it fits, and returning `text.left(character_limit - 1) + "…"` when it exceeds a positive limit. Implement `stat_entries` by appending only positive `damage`, `defense`, and `heal` values in that order, using `CardDetailStatSeal.Attribute` values.
- [ ] **Step 4: Implement the reusable `CardDetailStatSeal` scene and script**

Create `scenes/card_view/card_detail_stat_seal.tscn` as a `PanelContainer` named `CardDetailStatSeal`, with a centered `Label` child named `ValueLabel`. Set the root `mouse_filter` to `Control.MOUSE_FILTER_IGNORE`; use only editable `StyleBoxFlat` resources in the scene/script, with a 1 px border, 4 px rounded corners, 7 px horizontal content margins, 3 px vertical margins, and no shadow.

Create `scripts/card/card_detail_stat_seal.gd` with `class_name CardDetailStatSeal`. Define:

```gdscript
enum Attribute { DAMAGE, DEFENSE, HEAL }

const CONFIG := {
    Attribute.DAMAGE: {"label": "STRIKE", "background": Color("6f3938"), "border": Color("a45a50")},
    Attribute.DEFENSE: {"label": "GUARD", "background": Color("29465e"), "border": Color("5f87a6")},
    Attribute.HEAL: {"label": "MEND", "background": Color("28594f"), "border": Color("579785")},
}
```

`configure(attribute, value)` must set `ValueLabel.text` to `"%d %s" % [value, config.label]`, add the config's `font_color` as `Color("eee5cf")`, duplicate the normal `StyleBoxFlat` before changing `bg_color` and `border_color`, and never mutate a style resource shared by another seal. Fall back to the `DAMAGE` config for an invalid attribute.

- [ ] **Step 5: Run the focused shared-component test**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_detail_ui_test.gd
```

Expected: exit code `0`; the formatter returns English copy and the damage seal reads `8 STRIKE` with a muted red surface.
### Task 2: Rebuild the Hover Panel as a Field Note

**Files:**
- Modify: `scenes/card_view/card_info.tscn`
- Modify: `scripts/card/card_info.gd`
- Modify: `tests/card_info_overlay_test.gd`

**Interfaces:**
- Consumes `CardDetailFormat.stat_entries(data)` and `CardDetailStatSeal.configure(attribute, value)` from Task 1.
- Preserves `CardInfo.set_card(inst: CardInstance) -> void` and `CardInfo.refresh_display() -> void` for `CardInfoOverlay`.
- Preserves the ownership and positioning contract in `scripts/card/card_info_overlay.gd`: cards create their own `CanvasLayer`; the hover panel stays screen-upright, flips left when right space is unavailable, clamps to the viewport, ignores pointer input, and hides immediately on card exit.

- [ ] **Step 1: Extend the hover overlay test before changing the UI**

In `tests/card_info_overlay_test.gd`, after opening hover for a card with a weapon tag, assert the `CardInfo` panel contains these nodes and values:

```gdscript
var meta := panel.get_node_or_null("MarginContainer/Content/MetaLabel") as Label
var title := panel.get_node_or_null("MarginContainer/Content/TitleLabel") as Label
var stats := panel.get_node_or_null("MarginContainer/Content/Stats") as HBoxContainer
var description := panel.get_node_or_null("MarginContainer/Content/DescriptionLabel") as Label
var tags := panel.get_node_or_null("MarginContainer/Content/Tags") as FlowContainer
_expect(meta != null and meta.text.contains("COMMON") and meta.text.contains("CARD"), "field note shows English rarity and type")
_expect(title != null and not title.text.is_empty(), "field note shows the card name")
_expect(stats != null and stats.get_child_count() > 0, "field note shows non-zero stat seals")
_expect(description != null and description.autowrap_mode != TextServer.AUTOWRAP_OFF, "field note wraps its summary")
_expect(tags != null and tags.get_child_count() > 0, "field note shows English tags")
```

Keep the existing assertion that `panel.mouse_filter == Control.MOUSE_FILTER_IGNORE`, and add assertions that `panel.size.x` is at least `280.0` after layout and every child seal uses `Control.MOUSE_FILTER_IGNORE`.

- [ ] **Step 2: Run the hover test to verify it fails**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_info_overlay_test.gd
```

Expected: non-zero exit because the Field Note node hierarchy does not exist yet.

- [ ] **Step 3: Replace the basic hover scene with the Field Note hierarchy**

Rebuild `scenes/card_view/card_info.tscn` using this exact hierarchy:

```text
CardInfo (PanelContainer)
└── MarginContainer
    └── Content (VBoxContainer)
        ├── MetaLabel (Label)
        ├── TitleLabel (Label)
        ├── GoldRule (ColorRect)
        ├── Stats (HBoxContainer)
        ├── DescriptionLabel (Label)
        └── Tags (FlowContainer)
```

Set the root width to `320` and leave its height container-driven. Apply a dark ink-blue `StyleBoxFlat` (`#121b28`) with a 1 px antique-gold border (`#a8864b`), 6 px corner radius, 14 px content margins, and a restrained black shadow. Use bone-paper `#eee5cf` for the title, muted parchment `#b8ad94` for metadata and description, and `#8c713e` for the 1 px rule. The title uses the existing project display font if already assigned by the theme, falls back to the scene default otherwise, and is `22` px. Metadata is `12` px and uppercase. The description is `14` px, has `autowrap_mode = TextServer.AUTOWRAP_WORD_SMART`, and is capped at three visible lines with `max_lines_visible = 3`. Give the panel and all decorative children `mouse_filter = Control.MOUSE_FILTER_IGNORE`.

- [ ] **Step 4: Replace dynamic labels in `CardInfo` with formatted Field Note content**

In `scripts/card/card_info.gd`, replace the legacy Chinese tag mapping and emoji stat rendering. Bind these paths with typed `@onready` references:

```gdscript
@onready var meta_label: Label = $MarginContainer/Content/MetaLabel
@onready var title_label: Label = $MarginContainer/Content/TitleLabel
@onready var stats: HBoxContainer = $MarginContainer/Content/Stats
@onready var description_label: Label = $MarginContainer/Content/DescriptionLabel
@onready var tags: FlowContainer = $MarginContainer/Content/Tags
```

Preload `res://scenes/card_view/card_detail_stat_seal.tscn`. In `refresh_display`, return safely when the instance/data is absent; otherwise set `meta_label.text` to `"%s · %s" % [CardDetailFormat.rarity_name(data.rarity), CardDetailFormat.card_type_name(data.card_type)]`, set `title_label.text` to `data.card_name`, build one reusable detail-stat seal per `CardDetailFormat.stat_entries(data)` result, set description to `CardDetailFormat.compact_description(data.description)`, and rebuild tags as small uppercase labels using `CardDetailFormat.tag_name(tag)`. Each tag label must use muted ink-blue fill, `#4b6174` border, `#cfc4a8` text, a small flat style box, and `mouse_filter = IGNORE`. Hide the description label when the compact result is empty; hide the stats container when it has no seals; hide the tags container when the card has no tags.

Do not edit `scripts/card/card_info_overlay.gd` or move hover lifecycle logic into the scene: it already correctly owns screen-space placement and immediate hide behavior.

- [ ] **Step 5: Run the Field Note regression test**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_info_overlay_test.gd
```

Expected: exit code `0`; the new Field Note content exists while the existing upright, clamped, left/right-flip, and instant-hide assertions remain green.
### Task 3: Rebuild the Zoom Overlay as a Pilgrim’s Record

**Files:**
- Modify: `scenes/card_view/zoom_view.tscn`
- Modify: `scripts/card/card_zoom_view.gd`
- Modify: `scripts/card/card_entity.gd`
- Modify: `tests/card_zoom_overlay_test.gd`

**Interfaces:**
- Consumes `CardDetailFormat`, `CardDetailStatSeal`, and `res://scenes/card_view/card_view.tscn` from Tasks 1–2.
- Preserves `ZoomView.set_data(card_instance: CardInstance) -> void` for `CardEntity._show_zoom()`.
- `CardEntity._show_zoom()` must continue to create `CardZoomOverlay` at `RenderPriority.CARD_ZOOM_OVERLAY`; its full-screen `ZoomBg` remains the input-blocking backdrop and must close only for a click outside `ZoomView` or `ui_cancel`.

- [ ] **Step 1: Extend zoom coverage to describe the full record**

In `tests/card_zoom_overlay_test.gd`, after `card._show_zoom()` and one process frame, find `CardZoomOverlay/ZoomBg/ZoomView`, then assert:

```gdscript
var zoom_view := host.get_node_or_null("CardZoomOverlay/ZoomBg/ZoomView") as PanelContainer
var preview := zoom_view.get_node_or_null("SheetMargin/Sheet/ContentRow/CardPreviewHost/CardPreview") if zoom_view != null else null
var detail := zoom_view.get_node_or_null("SheetMargin/Sheet/ContentRow/DetailColumn") if zoom_view != null else null
var hint := zoom_view.get_node_or_null("SheetMargin/Sheet/CloseHint") as Label if zoom_view != null else null
_expect(zoom_view != null and zoom_view.mouse_filter == Control.MOUSE_FILTER_STOP, "record blocks clicks inside its sheet")
_expect(preview != null and preview.card_inst == card.card_instance, "record preview uses the opened CardInstance")
_expect(preview != null and preview.get_parent().mouse_filter == Control.MOUSE_FILTER_IGNORE, "record preview is display-only")
_expect(detail != null, "record includes a detail column")
_expect(hint != null and hint.text == "CLICK OUTSIDE OR PRESS ESC TO CLOSE", "record uses the approved English close hint")
```

Keep the full-rect background assertions. Add a test that invokes `_on_zoom_bg_input` with an event positioned inside `ZoomView` and verifies the overlay remains valid, then invokes it with a point outside the sheet and verifies `_zoom_overlay == null`. Finally open it again, send `InputEventAction` with `action = "ui_cancel"` and `pressed = true` through `_input`, and assert it closes.

- [ ] **Step 2: Run the zoom test to verify it fails**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_zoom_overlay_test.gd
```

Expected: non-zero exit because the current popup has no actual `CardView` preview, no record hierarchy, and closes on all backdrop clicks.

- [ ] **Step 3: Replace `zoom_view.tscn` with the two-column Pilgrim’s Record**

Rebuild `scenes/card_view/zoom_view.tscn` using this hierarchy:

```text
ZoomView (PanelContainer)
└── SheetMargin (MarginContainer)
    └── Sheet (PanelContainer)
        └── ContentRow (HBoxContainer)
            ├── CardPreviewHost (CenterContainer)
            └── DetailColumn (VBoxContainer)
                ├── MetaLabel (Label)
                ├── TitleLabel (Label)
                ├── CardIdLabel (Label)
                ├── GoldRuleTop (ColorRect)
                ├── Stats (HBoxContainer)
                ├── DescriptionLabel (Label)
                ├── GoldRuleBottom (ColorRect)
                └── Tags (FlowContainer)
    └── CloseHint (Label)
```

Give `ZoomView` a `860 × 510` minimum size and `MOUSE_FILTER_STOP`. Use an outer near-black panel `#0a1018` with a 1 px `#735c32` border and 12 px corner radius. Use an inner ink-blue sheet `#141f2d` with a 1 px antique-gold `#a8864b` border, 8 px radius, 24 px padding, and a low-opacity black shadow. Give `CardPreviewHost` a fixed `280 × 420` region; leave `DetailColumn` to fill the remaining width, with 20 px separation. Use #eee5cf title text at 34 px, #c3b79e metadata and ID at 14 px, #a8864b 1 px rules, and #d8cfbb description at 17 px with word-smart wrapping. Set `CloseHint` to 12 px muted parchment and exact uppercase text `CLICK OUTSIDE OR PRESS ESC TO CLOSE`. Use only Godot controls, local `StyleBoxFlat` resources, and the project’s current theme/fonts; do not add raster assets, bloom, or glow effects.

- [ ] **Step 4: Implement real preview and shared-detail rendering in `CardZoomView`**

In `scripts/card/card_zoom_view.gd`, remove duplicate rarity/tag constants and the unused `_process`. Preload both `card_view.tscn` and `card_detail_stat_seal.tscn`; bind the hierarchy from Step 3. Keep `set_data(card_instance: CardInstance) -> void`, assign `self.card_inst`, and if the node is already ready, call `refresh_display()`.

In `_ready`, preserve the debug-card fallback only when no data was supplied, then call `refresh_display`. In `refresh_display`, return when no card data exists, then:

1. Create `CardPreview` only once under `CardPreviewHost`; name it exactly `CardPreview`, call `set_value(card_inst)`, set its `custom_minimum_size` and `size` to `Vector2(252, 378)`, and call `set_display_only(true)` only if that method exists on the instantiated root. The preview must reference the exact original `CardInstance`.
2. Set metadata to `"%s · %s"`, title to `data.card_name`, and ID to `"RECORD %03d" % data.card_id` using `CardDetailFormat`.
3. Rebuild non-zero stat seals from `CardDetailFormat.stat_entries(data)`.
4. Use the full `data.description` for the record; hide its label when empty.
5. Rebuild uppercase English tag labels using the same muted tag style as Task 2; hide `Tags` when empty.

Make `refresh_display` idempotent: repeated calls must replace stats/tags and update the existing preview, not add a second preview. Do not reparent or duplicate the opening card’s in-world entity.

- [ ] **Step 5: Make backdrop closing distinguish inside from outside clicks**

In `scripts/card/card_entity.gd`, retain the existing overlay creation, render layer, display-only guard, `ui_cancel` path, `ZoomBg` full-rect anchors, and `_hide_zoom` lifecycle. Change only the backdrop interaction so `_on_zoom_bg_input` receives the mouse-button event and tests its `position` against the global rect of the `ZoomView` child. Call `_hide_zoom()` only when that press is outside the visible sheet. A click inside the sheet must be consumed by `ZoomView` and must never close the overlay. Change `ZoomBg.color` from pure black opacity to a restrained blue-black dimmer, `Color("070b12b8")`, without using a shader or glow.

- [ ] **Step 6: Run the Pilgrim’s Record regression test**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_zoom_overlay_test.gd
```

Expected: exit code `0`; the background covers the viewport, preview shares the opened instance, inside clicks remain open, outside clicks close, and `Esc` closes.
### Task 4: Verify the Detail UI and Perform Visual Acceptance

**Files:**
- Modify: `tests/card_detail_ui_test.gd`
- Modify: `tests/card_info_overlay_test.gd`
- Modify: `tests/card_zoom_overlay_test.gd`
- Verify: `scripts/game/render_priority.gd`

**Interfaces:**
- Confirms `RenderPriority.CARD_INFO_OVERLAY == 5` and `RenderPriority.CARD_ZOOM_OVERLAY == 128` remain the central authority for these layers.
- Confirms all public APIs remain unchanged: `CardInfo.set_card`, `CardInfo.refresh_display`, `ZoomView.set_data`, and `CardEntity` zoom entry/exit behavior.

- [ ] **Step 1: Add regressions for non-interaction and display-only preview**

In `tests/card_detail_ui_test.gd`, add one assertion for each `DAMAGE`, `DEFENSE`, and `HEAL` configuration verifying exact copy (`STRIKE`, `GUARD`, `MEND`) and that the background colors are distinct. In `tests/card_info_overlay_test.gd`, verify the Field Note root and its dynamically-created tag labels/seals have `mouse_filter == Control.MOUSE_FILTER_IGNORE`. In `tests/card_zoom_overlay_test.gd`, verify the preview is an in-tree `CardView` whose `is_display_only()` returns true, while the record root itself uses `Control.MOUSE_FILTER_STOP`.

- [ ] **Step 2: Run all affected scene tests**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_detail_ui_test.gd
& $godot --headless --path . --script tests\card_info_overlay_test.gd
& $godot --headless --path . --script tests\card_zoom_overlay_test.gd
& $godot --headless --path . --script tests\card_entity_display_mode_test.gd
& $godot --headless --path . --script tests\card_view_visual_scene_test.gd
```

Expected: every command exits `0`. If a pre-existing unrelated failure appears, preserve it and report its full command and failure; do not change unrelated gameplay code to make this UI work.

- [ ] **Step 3: Validate the project parses and whitespace is clean**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --editor --quit
git diff --check
git diff -- scripts/card/card_detail_format.gd scripts/card/card_detail_stat_seal.gd scenes/card_view/card_detail_stat_seal.tscn scripts/card/card_info.gd scenes/card_view/card_info.tscn scripts/card/card_zoom_view.gd scenes/card_view/zoom_view.tscn scripts/card/card_entity.gd tests/card_detail_ui_test.gd tests/card_info_overlay_test.gd tests/card_zoom_overlay_test.gd
```

Expected: Godot reports no parse/import errors; `git diff --check` produces no output; the focused diff contains only the intended detail UI changes and test updates.

- [ ] **Step 4: Complete manual acceptance at `1920 × 1080`**

Run the game through the normal main-menu flow, begin a run, and inspect an in-world card with a non-zero combat stat and at least one tag.

Confirm all of the following:

1. Hover opens a compact upright Field Note beside the card and it immediately disappears when the pointer leaves.
2. A rotated card leaves the Field Note horizontal to the screen, never spins with the card, and the note stays inside the viewport at both screen edges.
3. The Field Note is subdued: dark ink-blue surface, fine antique-gold frame, bone-paper title, short English stat seals, English tags, and no Chinese copy or emoji stat glyphs.
4. Right-click opens a restrained full-screen blue-black dimmer and centered Pilgrim’s Record. Its left preview is a genuine card, visually larger but not interactive; its right record content has the same English data as the card.
5. Clicking the card preview or any record detail does not close the overlay; clicking outside the sheet or pressing `Esc` closes it.
6. Dragging, standard left-click selection, display-only cards, and `RenderPriority` stacking retain their prior behavior.

## Plan Self-Review

- Every approved visual requirement maps to Tasks 1–3: shared muted seals, compact Field Note, full Pilgrim’s Record, exact English copy, real `CardView` preview, and blue-black dimmer.
- The existing card-owned overlay lifecycle and `RenderPriority` settings are explicitly preserved and regression-tested in Tasks 2–4.
- The plan names every create/modify/test file and provides exact scene paths, API contracts, palette values, and executable validation commands.
- No workflow step creates a branch, stages files, or commits changes; this respects the project instruction to avoid commits unless the user explicitly requests one.