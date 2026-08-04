# Card Paper Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a nearly flat, editable paper-edge depth treatment to each procedural card rarity frame.

**Architecture:** The four rarity frame `.tscn` files already fill `CardView/FrameHost` and contain the front-facing border layers. Add two `Panel` nodes behind those existing layers: `SoftShadow` at `(1, 2)` and `PaperCore` at `(1, 1)`. Both use per-scene `StyleBoxFlat` resources, so paper depth remains editable in the Godot Inspector and rotates as part of the existing card entity.

**Tech Stack:** Godot 4.7, `.tscn` scenes, `StyleBoxFlat`, GDScript scene-tree tests.

## Global Constraints

- Do not use PNG frame assets from `assert/card_frame/`.
- Do not add textures, shaders, glow, or external art resources.
- Maintain the existing `COMMON`, `RARE`, `EPIC`, and `LEGENDARY` front-border colors and header accents.
- Use exactly `SoftShadow` and `PaperCore` node names in every rarity frame scene.
- Keep the shadow at `Vector2(1, 2)` with alpha below `0.25`.
- Keep the paper edge at `Vector2(1, 1)` and do not alter card layout, dimensions, combat tags, or rotation logic. Remove only the obsolete `NamePlate/NameLabel` script and test dependency, because the title plate was intentionally removed from `card_view.tscn`.
- Do not create a commit; this worktree contains unrelated in-progress changes and the user has not requested one.

---

### Task 1: Cover paper-depth frame layers

**Files:**
- Modify: `tests/card_view_visual_scene_test.gd:18-43`

**Interfaces:**
- Consumes: the four existing paths in `FRAME_SCENE_PATHS`.
- Produces: a test contract requiring every rarity `PackedScene` root to expose `SoftShadow` and `PaperCore` as `Panel` nodes.

- [ ] **Step 1: Write the failing test**

Add this method and call it immediately after `_test_editable_visual_scenes_exist()` in `_run_tests()`:

```gdscript
func _test_rarity_frames_include_subtle_paper_depth() -> void:
    for scene_path in FRAME_SCENE_PATHS:
        var frame := load(scene_path).instantiate() as Control
        var soft_shadow := frame.get_node_or_null("SoftShadow") as Panel
        var paper_core := frame.get_node_or_null("PaperCore") as Panel
        _expect(soft_shadow != null, "%s exposes a soft paper shadow" % scene_path)
        _expect(paper_core != null, "%s exposes a paper core edge" % scene_path)
        if soft_shadow != null:
            _expect(soft_shadow.position == Vector2(1.0, 2.0), "%s keeps its shadow subtle" % scene_path)
        if paper_core != null:
            _expect(paper_core.position == Vector2(1.0, 1.0), "%s keeps its paper edge subtle" % scene_path)
        frame.free()
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_view_visual_scene_test.gd
```

Expected: exit code `1` and failures stating that `SoftShadow` and `PaperCore` are missing from the current rarity-frame scenes.

- [ ] **Step 3: Do not commit**

The user did not request a commit and the workspace includes unrelated active modifications. Leave all changed files unstaged.

### Task 2: Add editable paper-depth layers to rarity scenes

**Files:**
- Modify: `scenes/card_view/frames/card_frame_common.tscn:1-76`
- Modify: `scenes/card_view/frames/card_frame_rare.tscn:1-76`
- Modify: `scenes/card_view/frames/card_frame_epic.tscn:1-76`
- Modify: `scenes/card_view/frames/card_frame_legendary.tscn:1-76`
- Test: `tests/card_view_visual_scene_test.gd`

**Interfaces:**
- Consumes: Task 1's expected `SoftShadow` and `PaperCore` nodes.
- Produces: four self-contained `PackedScene` frames whose visual order is `SoftShadow`, `PaperCore`, `OuterBorder`, `InnerBorder`, `HeaderAccent`.

- [ ] **Step 1: Add two shared layer resources to every frame scene**

Add a `StyleBoxShadow` resource with a near-black blue-charcoal fill below 25% alpha and no border. Add a `StyleBoxPaperCore` resource with a matte warm-brown fill and a very dark-brown 1 px bottom/right border. Keep their corner radii aligned to the existing outer frame.

Use this common shape; only the paper-core hue may shift slightly to harmonize with each rarity:

```text
StyleBoxShadow
  bg_color: blue-charcoal, alpha 0.20–0.24
  corner radius: matches outer frame

StyleBoxPaperCore
  bg_color: muted brown-black paper edge, alpha 0.94–0.98
  border_width_right: 1
  border_width_bottom: 1
  border_color: dark brown-black
  corner radius: matches outer frame
```

- [ ] **Step 2: Insert depth panels behind front-frame layers**

Immediately after `CardFrame`, before `OuterBorder`, insert these nodes in every frame scene:

```ini
[node name="SoftShadow" type="Panel" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 1.0
offset_top = 2.0
offset_right = 1.0
offset_bottom = 2.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
theme_override_styles/panel = SubResource("StyleBoxShadow")

[node name="PaperCore" type="Panel" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 1.0
offset_top = 1.0
offset_right = 1.0
offset_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
theme_override_styles/panel = SubResource("StyleBoxPaperCore")
```

- [ ] **Step 3: Preserve front-frame nodes without script changes**

Leave `OuterBorder`, `InnerBorder`, and `HeaderAccent` after the two new panels. Do not modify `scripts/card/card_entity.gd`, the combat tag scenes, or `card_view.tscn`. Remove the obsolete `@onready var name_label` declaration from `scripts/card/card_view.gd`; the title plate was intentionally removed, and the existing parent transforms make the new layers rotate with the card.

- [ ] **Step 4: Run the focused visual test to verify it passes**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\card_view_visual_scene_test.gd
```

Expected: exit code `0` with no `push_error` output.

- [ ] **Step 5: Do not commit**

The user did not request a commit and the workspace includes unrelated active modifications. Leave all changed files unstaged.

### Task 3: Validate scene parsing and patch hygiene

**Files:**
- Verify: `scenes/card_view/frames/card_frame_common.tscn`
- Verify: `scenes/card_view/frames/card_frame_rare.tscn`
- Verify: `scenes/card_view/frames/card_frame_epic.tscn`
- Verify: `scenes/card_view/frames/card_frame_legendary.tscn`
- Verify: `tests/card_view_visual_scene_test.gd`

**Interfaces:**
- Consumes: the completed visual test and all four modified scenes.
- Produces: evidence that Godot parses every frame scene and the patch contains no whitespace errors.

- [ ] **Step 1: Run the Godot editor load check**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --editor --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

Expected: exit code `0`. Any nonzero exit code or scene parser error blocks completion.

- [ ] **Step 2: Run diff validation**

Run:

```powershell
git diff --check
```

Expected: exit code `0` with no output.

- [ ] **Step 3: Do not commit**

The user did not request a commit and the workspace includes unrelated active modifications. Leave all changed files unstaged.

## Plan Self-Review

- **Spec coverage:** Task 1 locks in the exact reusable node interface; Task 2 adds the two editable scenes layers, applies the exact lightweight offsets, preserves rarity colors, and leaves layouts/scripts untouched; Task 3 validates parsing and whitespace.
- **Constraint coverage:** The plan explicitly excludes PNG frame assets, textures, shaders, glow, external art, thick offsets, runtime logic edits, layout changes, and commits.
- **Type consistency:** Every task uses `SoftShadow` and `PaperCore` as `Panel` nodes, and all test paths come from the existing `FRAME_SCENE_PATHS` list.
- **Placeholder scan:** No `TODO`, `TBD`, undefined helper methods, or ambiguous implementation instructions remain.