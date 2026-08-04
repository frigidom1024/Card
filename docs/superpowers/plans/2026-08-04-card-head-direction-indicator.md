# 卡牌头部方向箭头实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在牌桌卡牌的 `CardView` 顶部外侧增加一个无文字、发光的箭头，并保证它随卡牌的 90° 旋转同步指示牌头方向。

**Architecture:** 箭头作为 `CardView` 场景内的 `HeadIndicator` 局部子节点实现，不使用 `CardEntity` 的全局标签定位逻辑。`card_view.gd` 只负责在尺寸变化时把该节点水平居中、垂直锚定到卡牌顶部外侧；箭头本身由场景中的多层 `Polygon2D` 组成，用半透明底层模拟辉光。由于它属于 `CardView`，现有 `CardEntity.rotation_degrees` 会自然传递给箭头。

**Tech Stack:** Godot 4.x、GDScript、`.tscn` 场景、`Polygon2D`、现有 `SceneTree` 视觉测试。

## Global Constraints

- 箭头必须位于 `CardView` 场景中，不新增 `CardEntity` 的全局浮层。
- 箭头不显示任何文字，只使用几何箭头结构。
- 箭头必须随卡牌旋转，不保持屏幕正向。
- 箭头不得拦截鼠标、拖拽或点击输入，`mouse_filter` 使用 `MOUSE_FILTER_IGNORE`。
- 不修改 `CardInstance.direction`、卡牌旋转输入和现有 `CombatTagAnchor` 逻辑。
- 不新增外部图片资源；辉光使用场景中的半透明几何层。
- 保留工作区现有与本功能无关的 Godot 修改，不使用 `git add -A`。

---

## 文件结构与职责

- Modify: `D:/project/MonoCard/mono-card/scenes/card_view/card_view.tscn`
  - 新增 `HeadIndicator` 根节点及 `ArrowGlow`、`ArrowBody` 几何层。
- Modify: `D:/project/MonoCard/mono-card/scripts/card/card_view.gd`
  - 维护箭头尺寸、顶部外延位置和尺寸变化响应。
- Modify: `D:/project/MonoCard/mono-card/tests/card_view_visual_scene_test.gd`
  - 添加箭头存在性、可见性、顶部定位、输入穿透和旋转同步测试。
- Reference only: `D:/project/MonoCard/mono-card/scripts/card/card_entity.gd`
  - 验证现有旋转和战斗标签逻辑无需修改。

### Task 1: Add the failing visual-scene regression test

**Files:**
- Modify: `D:/project/MonoCard/mono-card/tests/card_view_visual_scene_test.gd`

**Interfaces:**
- Consumes: Existing `CardViewScene`, `SceneTree`, and `_expect()` helper.
- Produces: A failing test named `_test_card_view_head_indicator_points_outward_and_rotates_with_card` that defines the required scene contract for the later scene and script changes.

- [ ] **Step 1: Register the test in `_run_tests()`**

Add the call after the existing CardView visual host tests and before the combat-tag rotation test:

```gdscript
await _test_card_view_head_indicator_points_outward_and_rotates_with_card()
```

- [ ] **Step 2: Write the failing test**

Add this test method. The polygon point-count check keeps the test focused on an actual arrow geometry instead of only checking that a generic control exists:

```gdscript
func _test_card_view_head_indicator_points_outward_and_rotates_with_card() -> void:
	var view := CardViewScene.instantiate() as Control
	root.add_child(view)
	await process_frame

	var indicator := view.get_node_or_null("HeadIndicator") as Control
	var glow := view.get_node_or_null("HeadIndicator/ArrowGlow") as Polygon2D
	var body := view.get_node_or_null("HeadIndicator/ArrowBody") as Polygon2D
	_expect(indicator != null, "card view exposes a head direction indicator")
	_expect(indicator != null and indicator.visible, "head direction indicator is visible on the table card view")
	_expect(indicator != null and indicator.mouse_filter == Control.MOUSE_FILTER_IGNORE, "head direction indicator does not intercept pointer input")
	_expect(glow != null and glow.polygon.size() >= 5, "head indicator exposes a geometric glow arrow")
	_expect(body != null and body.polygon.size() >= 5, "head indicator exposes a geometric body arrow")

	if indicator != null:
		_expect(indicator.position.x > 0.0 and indicator.position.x + indicator.size.x < view.size.x, "head indicator is horizontally centered within the card")
		_expect(indicator.position.y + indicator.size.y < 0.0, "head indicator is outside the card's top edge")

	var rotation_before := indicator.global_rotation
	view.rotation = PI / 2.0
	await process_frame
	if indicator != null:
		_expect(is_equal_approx(indicator.global_rotation, view.global_rotation), "head indicator rotates with the card view")
		_expect(not is_equal_approx(rotation_before, indicator.global_rotation), "head indicator changes orientation when the card rotates")

	view.free()
	await process_frame
```

- [ ] **Step 3: Run the focused test and verify it fails for the missing scene contract**

Run:

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/card_view_visual_scene_test.gd
```

Expected: non-zero exit because `HeadIndicator`, `ArrowGlow`, and `ArrowBody` do not yet exist.

### Task 2: Add the arrow layers and position them from CardView dimensions

**Files:**
- Modify: `D:/project/MonoCard/mono-card/scenes/card_view/card_view.tscn`
- Modify: `D:/project/MonoCard/mono-card/scripts/card/card_view.gd`

**Interfaces:**
- Consumes: Task 1's required node paths `HeadIndicator`, `HeadIndicator/ArrowGlow`, and `HeadIndicator/ArrowBody`.
- Produces: A visible, non-interactive local arrow whose tip points toward negative local Y and whose bottom sits just above the card's top edge.

- [ ] **Step 1: Add the scene nodes with explicit local geometry**

Append a `Control` after `FrameHost` and before the bottom label layer. Configure it with `mouse_filter = 2`, `z_index = 20`, and a size of `28 × 14`. Add two `Polygon2D` children using the same seven-point arrow silhouette:

```gdscript
[node name="HeadIndicator" type="Control" parent="."]
offset_left = 0.0
offset_top = -16.0
offset_right = 28.0
offset_bottom = -2.0
mouse_filter = 2
z_index = 20

[node name="ArrowGlow" type="Polygon2D" parent="HeadIndicator"]
polygon = PackedVector2Array(14, 0, 28, 9, 19, 9, 19, 14, 9, 14, 9, 9, 0, 9)
color = Color(0.18, 0.82, 0.92, 0.28)

[node name="ArrowBody" type="Polygon2D" parent="HeadIndicator"]
polygon = PackedVector2Array(14, 1, 26, 9, 18, 9, 18, 13, 10, 13, 10, 9, 2, 9)
color = Color(0.48, 0.92, 0.96, 0.95)
```

The larger translucent polygon is the glow silhouette; the inset polygon is the crisp arrow core. Both point toward negative local Y.

- [ ] **Step 2: Add dimension-based positioning in `card_view.gd`**

Add constants and an `@onready` reference:

```gdscript
const HEAD_INDICATOR_SIZE := Vector2(28.0, 14.0)
const HEAD_INDICATOR_GAP := 2.0

@onready var head_indicator: Control = $HeadIndicator
```

Connect the existing `resized` signal to a new `_pin_head_indicator()` method and call it from `_ready()` alongside `_pin_label_container()`:

```gdscript
resized.connect(_pin_head_indicator)
_pin_head_indicator()

func _pin_head_indicator() -> void:
	if head_indicator == null:
		return
	head_indicator.size = HEAD_INDICATOR_SIZE
	head_indicator.position = Vector2(
		(size.x - HEAD_INDICATOR_SIZE.x) * 0.5,
		-HEAD_INDICATOR_SIZE.y - HEAD_INDICATOR_GAP,
	)
```

This makes the arrow remain centered when `CardEntity._apply_layout()` changes the CardView rectangle. Do not change `rotation` or `global_position`; local parenting is what preserves rotation synchronization.

- [ ] **Step 3: Run the focused test and verify it passes**

Run:

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/card_view_visual_scene_test.gd
```

Expected: exit code 0 with no new assertion failures.

### Task 3: Run the regression suite and inspect the visual diff

**Files:**
- Test only: `D:/project/MonoCard/mono-card/tests/card_view_visual_scene_test.gd`
- Review only: `D:/project/MonoCard/mono-card/scenes/card_view/card_view.tscn`

**Interfaces:**
- Consumes: Task 2's fixed node names and local positioning behavior.
- Produces: Verified compatibility with rarity frames, artwork layers, placeholder behavior, and upright combat tags.

- [ ] **Step 1: Run the complete card-view visual test**

Run:

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/card_view_visual_scene_test.gd
```

Expected: exit code 0; existing artwork, placeholder, frame, and combat-tag assertions remain passing.

- [ ] **Step 2: Run related card entity tests**

Run:

```powershell
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/card_entity_display_mode_test.gd
godot --headless --path D:/project/MonoCard/mono-card --script res://tests/layout_config_test.gd
```

Expected: both commands exit 0; no display-mode or layout regressions.

- [ ] **Step 3: Check the patch scope before committing**

Run:

```powershell
git diff --check -- scenes/card_view/card_view.tscn scripts/card/card_view.gd tests/card_view_visual_scene_test.gd
git status --short -- scenes/card_view/card_view.tscn scripts/card/card_view.gd tests/card_view_visual_scene_test.gd
```

Expected: no whitespace errors and only the three feature files are listed as modified.

- [ ] **Step 4: Commit only the feature files**

Run:

```powershell
git add -- scenes/card_view/card_view.tscn scripts/card/card_view.gd tests/card_view_visual_scene_test.gd
git commit -m "feat: add glowing card head direction arrow"
```

Do not stage unrelated existing Godot changes.
## Acceptance Checklist

- `HeadIndicator` is visible above the card's top edge and horizontally centered.
- `ArrowGlow` and `ArrowBody` are geometric arrow layers with no text nodes or external image resources.
- The indicator uses `MOUSE_FILTER_IGNORE` and does not alter existing card input behavior.
- Rotating the CardView changes the indicator's global orientation with the card.
- Focused and related Godot tests exit with code 0.
- The feature commit includes only the three scoped feature files.
