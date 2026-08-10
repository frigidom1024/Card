# Ribwood Card Effect Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all 19 Ribwood cards conform to the approved point/armor balance and clear card-rule descriptions, while adding three limited, placement-time synergy rules.

**Architecture:** Card placement remains the only rule-resolution point. `CardChainRuleService.resolve_card_added(chain, added_card)` iterates each source `CardInstance` currently in the chain, checks the source instance's per-rule successful-trigger limit, and gives each `CardRule` a `CardChainRuleContext`. New rule classes only query that context and mutate the newly added card's runtime points or armor; combat, event handling, faith, and exploration do not change.

**Tech Stack:** Godot 4.7, GDScript, `.tres` Resource data, headless SceneTree test scripts.

## Global Constraints

- Store planning and design documentation in `docs/design`; do **not** write new files below a `superpower` / `superpowers` directory.
- Work on the existing `master` worktree without resetting, cleaning, checking out over, or reverting existing uncommitted changes.
- Do not change `CombatService`, residual-echo strengthening, faith, event spawning, Boss pursuit, or UI rendering for this feature.
- `CardRule.effective_count`: `-1` means unlimited successful triggers; `0` means disabled; a positive value caps successful triggers per owning `CardInstance` and rule index.
- A rule returns `true` only after it actually adds a positive amount of points or armor. The service consumes a use only for `true` returns.
- Rule descriptions must say trigger time, target/position, numeric result, and finite-use text where applicable. Cards without a rule must end in `无额外效果。`.
- Preserve resource paths and existing `card_id` values; use Godot-loadable external script resources in all edited `.tres` files.
- Before committing, inspect the staged diff. The repository already contains unrelated unstaged changes, including several Ribwood resources; never use `git add .`.

---

## File Structure

### New runtime rules

- `scripts/combatv2/card/rules/armored_next_card_point_bonus_rule.gd` — grants points to a newly added card only when it is directly ahead of the source and currently has armor.
- `scripts/combatv2/card/rules/chain_length_head_point_bonus_rule.gd` — grants points to the newly added head when the chain has reached a configured minimum length.
- `scripts/combatv2/card/rules/chain_length_head_armor_bonus_rule.gd` — armor counterpart to the prior rule.

### Runtime API extension

- `scripts/combatv2/card/card_chain_rule_context.gd` — adds a narrow `added_card_has_armor()` query, so conditional rules do not inspect private context state.

### Data and tests

- `data/levels/ribwood/cards/*.tres` — 19 approved Ribwood card resources: point value, starting armor, internal price, rarity, complete description, and the correct `effect_rules` resource.
- `tests/card_chain_rule_service_test.gd` — rule-level semantics for the three new `CardRule` classes and count consumption.
- `tests/ribwood_card_data_test.gd` — data contract for the complete card pool and descriptive copy rules.
- `tests/ribwood_card_rules_test.gd` — integration tests using the actual Ribwood card resource configuration.
- `tests/ribwood_combat_balance_test.gd` — retain the 4-HP Marrow Rat starter-chain verification.

## Task 1: Define the extended placement-rule contract with tests

**Files:**
- Modify: `scripts/combatv2/card/card_chain_rule_context.gd`
- Modify: `tests/card_chain_rule_service_test.gd`

**Interfaces:**
- Consumes: `CardChainRuleService.resolve_card_added(chain: Array[CardInstance], added_card: CardInstance) -> int`.
- Produces: `CardChainRuleContext.added_card_has_armor() -> bool`, which returns the new card's current armor state after earlier source rules in the same placement have run.

- [ ] **Step 1: Add failing service tests for all three conditional rules**

Add preloads for the planned rule scripts, add these calls to `_run_tests()`, and implement test bodies that construct `CardData` / `CardInstance` values with `_card()`:

```gdscript
_test_armored_next_card_requires_current_armor()
_test_chain_length_head_point_rule_requires_head_and_threshold()
_test_chain_length_head_armor_rule_respects_effective_count()
```

The armored-next test must verify these exact outcomes:

```gdscript
# source -> unarmored added: no application, 1 point remains, trigger count remains 0.
# A single source owns NextCardArmorBonusRule followed by ArmoredNextCardPointBonusRule:
# the first rule grants the directly adjacent added card 1 armor, the second sees
# current_armor == 1, grants +2 points, and only then increments its own count.
# This ordering is required because only one source can be directly behind one added card.
```

The chain-length point test must verify:

```gdscript
# threshold = 4; chain [root, source, spacer, head] grants +2 points to head.
# chain [root, source, added] does not grant because size is 3.
# resolving an already non-head card in [root, source, added, later_head]
# does not grant and does not consume a count.
```

The armor counterpart test must configure `minimum_chain_size = 4`, `armor = 2`, and `effective_count = 1`; it must verify that the first qualifying head gains exactly 2 armor, the source count becomes 1, and the next qualifying head gains no armor.

- [ ] **Step 2: Run the focused test and verify compilation fails before implementation**

Run:

```powershell
$godot='D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script res://tests/card_chain_rule_service_test.gd
```

Expected: parse/load failure because the three new rule scripts and `added_card_has_armor()` do not yet exist.

- [ ] **Step 3: Add the context query**

Insert this method after `is_added_card_head()` in `card_chain_rule_context.gd`:

```gdscript
## Evaluated at placement-rule resolution time, after any earlier rules may
## have granted armor to this same newly added card.
func added_card_has_armor() -> bool:
	return _added_card != null and _added_card.current_armor > 0
```

Do not add setters, card traversal, or count tracking to the context; those remain owned by `CardInstance` and `CardChainRuleService`.

- [ ] **Step 4: Run the focused test again**

Run the same command. Expected: failure now identifies the missing rule script/classes rather than a context API error.

- [ ] **Step 5: Stage only the context/test portion after review**

Inspect only this task's work:

```powershell
git diff -- scripts/combatv2/card/card_chain_rule_context.gd tests/card_chain_rule_service_test.gd
git diff --check -- scripts/combatv2/card/card_chain_rule_context.gd tests/card_chain_rule_service_test.gd
```

Do not commit yet if the test file also carries unrelated changes. Otherwise stage only these exact paths after Task 2 makes the test executable.

## Task 2: Implement the three placement-time CardRule classes

**Files:**
- Create: `scripts/combatv2/card/rules/armored_next_card_point_bonus_rule.gd`
- Create: `scripts/combatv2/card/rules/armored_next_card_point_bonus_rule.gd.uid`
- Create: `scripts/combatv2/card/rules/chain_length_head_point_bonus_rule.gd`
- Create: `scripts/combatv2/card/rules/chain_length_head_point_bonus_rule.gd.uid`
- Create: `scripts/combatv2/card/rules/chain_length_head_armor_bonus_rule.gd`
- Create: `scripts/combatv2/card/rules/chain_length_head_armor_bonus_rule.gd.uid`
- Modify: `tests/card_chain_rule_service_test.gd`

**Interfaces:**
- Consumes: `CardRule.execute_on_card_added(context: CardChainRuleContext) -> bool`, `CardChainRuleContext.is_added_card_next_to_source()`, `.is_added_card_head()`, `.get_chain_size()`, `.added_card_has_armor()`, `.add_points_to_added_card(amount)`, and `.add_armor_to_added_card(amount)`.
- Produces: three script classes usable as typed `CardData.effect_rules` resources: `ArmoredNextCardPointBonusRule`, `ChainLengthHeadPointBonusRule`, and `ChainLengthHeadArmorBonusRule`.

- [ ] **Step 1: Create the armor-conditioned adjacent-point rule**

Create `armored_next_card_point_bonus_rule.gd` with exactly this public configuration and resolution sequence:

```gdscript
class_name ArmoredNextCardPointBonusRule
extends CardRule

@export_range(1, 999, 1) var bonus_points: int = 1

func execute_on_card_added(context: CardChainRuleContext) -> bool:
	if context == null:
		return false
	if not context.is_added_card_next_to_source() or not context.added_card_has_armor():
		return false
	return context.add_points_to_added_card(bonus_points) > 0
```

Generate the `.uid` by opening/loading the script with Godot; do not invent a UID string.

- [ ] **Step 2: Create the chain-length head point rule**

Create `chain_length_head_point_bonus_rule.gd`:

```gdscript
class_name ChainLengthHeadPointBonusRule
extends CardRule

@export_range(2, 999, 1) var minimum_chain_size: int = 4
@export_range(1, 999, 1) var bonus_points: int = 1

func execute_on_card_added(context: CardChainRuleContext) -> bool:
	if context == null:
		return false
	if not context.is_added_card_head() or context.get_chain_size() < minimum_chain_size:
		return false
	return context.add_points_to_added_card(bonus_points) > 0
```

A source missing from the chain cannot pass the service traversal, so no duplicate source-membership condition belongs in the rule class.

- [ ] **Step 3: Create the chain-length head armor rule**

Create `chain_length_head_armor_bonus_rule.gd`:

```gdscript
class_name ChainLengthHeadArmorBonusRule
extends CardRule

@export_range(2, 999, 1) var minimum_chain_size: int = 4
@export_range(1, 999, 1) var armor: int = 1

func execute_on_card_added(context: CardChainRuleContext) -> bool:
	if context == null:
		return false
	if not context.is_added_card_head() or context.get_chain_size() < minimum_chain_size:
		return false
	return context.add_armor_to_added_card(armor) > 0
```

- [ ] **Step 4: Run the complete CardRule unit suite**

Run:

```powershell
& $godot --headless --path . --script res://tests/card_chain_rule_service_test.gd
& $godot --headless --path . --script res://tests/combatv2_card_rule_test.gd
```

Expected: both exit code `0`; the first proves conditions/counts and the second proves the unchanged base `CardRule` contract.

- [ ] **Step 5: Safely commit the isolated runtime change when its staged diff is clean**

First verify that the index contains no unrelated file:

```powershell
git add scripts/combatv2/card/card_chain_rule_context.gd scripts/combatv2/card/rules/armored_next_card_point_bonus_rule.gd scripts/combatv2/card/rules/armored_next_card_point_bonus_rule.gd.uid scripts/combatv2/card/rules/chain_length_head_point_bonus_rule.gd scripts/combatv2/card/rules/chain_length_head_point_bonus_rule.gd.uid scripts/combatv2/card/rules/chain_length_head_armor_bonus_rule.gd scripts/combatv2/card/rules/chain_length_head_armor_bonus_rule.gd.uid tests/card_chain_rule_service_test.gd
git diff --cached --check
git diff --cached --name-only
```

Only if the name list is exactly the files above, commit:

```powershell
git commit -m "feat(cards): add ribwood placement synergy rules"
```

If any staged file is unrelated, unstage only that file with `git restore --staged -- <unrelated-path>` and repeat the inspection; do not reset the worktree.

## Task 3: Convert all 19 Ribwood resources to the approved card pool

**Files:**
- Modify: `data/levels/ribwood/cards/ribwood_guardian_root.tres`
- Modify: `data/levels/ribwood/cards/ribwood_rib_blade.tres`
- Modify: `data/levels/ribwood/cards/ribwood_old_tinder.tres`
- Modify: `data/levels/ribwood/cards/ribwood_folded_rib_shield.tres`
- Modify: `data/levels/ribwood/cards/ribwood_warm_marrow_flask.tres`
- Modify: `data/levels/ribwood/cards/ribwood_rib_nail.tres`
- Modify: `data/levels/ribwood/cards/ribwood_shield_fragment.tres`
- Modify: `data/levels/ribwood/cards/ribwood_amber_marrow_bottle.tres`
- Modify: `data/levels/ribwood/cards/ribwood_bone_armor_round_shield.tres`
- Modify: `data/levels/ribwood/cards/ribwood_ember_blade.tres`
- Modify: `data/levels/ribwood/cards/ribwood_warmth_charm.tres`
- Modify: `data/levels/ribwood/cards/ribwood_scar_bottle.tres`
- Modify: `data/levels/ribwood/cards/ribwood_grave_beetle.tres`
- Modify: `data/levels/ribwood/cards/ribwood_bone_stitch_needle.tres`
- Modify: `data/levels/ribwood/cards/ribwood_old_chest_cloak.tres`
- Modify: `data/levels/ribwood/cards/ribwood_last_stand_strike.tres`
- Modify: `data/levels/ribwood/cards/ribwood_white_horn_relic.tres`
- Modify: `data/levels/ribwood/cards/ribwood_sternum_plate.tres`
- Modify: `data/levels/ribwood/cards/ribwood_guardian_ember.tres`

**Interfaces:**
- Consumes: `CardData` fields `value`, `max_points`, `armor`, `rarity`, `description`, and `effect_rules`; Task 2's rule script paths.
- Produces: Godot-loadable card resources used unchanged by `event_content/*.tres` reward pools and `data/starting_decks/revival_starting_deck.tres`.

- [ ] **Step 1: Make resources testable before data edits**

In `tests/ribwood_card_data_test.gd`, preload every resource listed above and add helper assertions:

```gdscript
func _expect_card(
	card: CardData, points: int, armor: int, value: int, rarity: CardData.Rarity, text: String
) -> void:
	_expect(card.max_points == points, "%s has expected points" % card.card_name)
	_expect(card.armor == armor, "%s has expected armor" % card.card_name)
	_expect(card.value == value, "%s has expected value" % card.card_name)
	_expect(card.rarity == rarity, "%s has expected rarity" % card.card_name)
	_expect(card.description == text, "%s has exact player-facing description" % card.card_name)
```

Add `_test_full_ribwood_card_pool_contract()` and assert all 19 rows exactly as defined in `docs/design/2026-08-10-ribwood-card-effect-refresh-design.md` section 4. Check no-rule cards with `effect_rules.is_empty()` and check each rule card's concrete script, configuration fields, and `effective_count`:

```gdscript
# Rib Blade: NextCardPointBonusRule, bonus_points=1, effective_count=-1
# Folded Rib Shield: NextCardArmorBonusRule, armor=1, effective_count=-1
# Shield Fragment: NextCardArmorBonusRule, armor=2, effective_count=1
# Bone Armor Round Shield: NextCardArmorBonusRule, armor=2, effective_count=2
# Ember Blade: ChainLengthHeadPointBonusRule, minimum_chain_size=4, bonus_points=2, effective_count=1
# Warmth Charm: ChainLengthHeadArmorBonusRule, minimum_chain_size=4, armor=2, effective_count=1
# Bone Stitch Needle: ArmoredNextCardPointBonusRule, bonus_points=2, effective_count=2
# Sternum Plate: NextCardArmorBonusRule, armor=2, effective_count=1
```

For descriptions, include the exact Chinese strings from the approved design document; this makes all player-visible effect text a data contract.

- [ ] **Step 2: Run the data test and confirm it fails against the pre-refresh resources**

Run:

```powershell
& $godot --headless --path . --script res://tests/ribwood_card_data_test.gd
```

Expected: failures for prices, armor/points, rare/epic rarity, rule types/configuration, and descriptions not yet matching the approved pool.

- [ ] **Step 3: Update base data and descriptive copy for each resource**

Apply the following exact data matrix. `P/A` is `max_points` / `armor`; `value` is the internal value or shop price; `C`, `R`, and `E` mean `COMMON`, `RARE`, and `EPIC`.

| Resource | Card | P/A | value | rarity | effect rule |
|---|---|---:|---:|---|---|
| `ribwood_guardian_root.tres` | 守护之根 | 2/0 | 1 | C | none |
| `ribwood_rib_blade.tres` | 肋骨短刃 | 2/0 | 4 | C | next +1 points, -1 |
| `ribwood_old_tinder.tres` | 旧火绒 | 1/0 | 3 | C | none |
| `ribwood_folded_rib_shield.tres` | 折叠肋盾 | 1/1 | 4 | C | next +1 armor, -1 |
| `ribwood_warm_marrow_flask.tres` | 温髓水囊 | 1/1 | 4 | C | none |
| `ribwood_rib_nail.tres` | 肋骨穿钉 | 3/0 | 8 | C | none |
| `ribwood_shield_fragment.tres` | 肋盾残片 | 1/1 | 8 | C | next +2 armor, 1 |
| `ribwood_amber_marrow_bottle.tres` | 琥珀骨髓瓶 | 2/2 | 8 | C | none |
| `ribwood_bone_armor_round_shield.tres` | 骨甲圆盾 | 1/2 | 8 | C | next +2 armor, 2 |
| `ribwood_ember_blade.tres` | 余烬短刃 | 3/0 | 10 | R | length 4 head +2 points, 1 |
| `ribwood_warmth_charm.tres` | 余温护符 | 2/1 | 10 | R | length 4 head +2 armor, 1 |
| `ribwood_scar_bottle.tres` | 结痂药瓶 | 2/2 | 8 | C | none |
| `ribwood_grave_beetle.tres` | 守墓甲虫 | 3/2 | 14 | R | none |
| `ribwood_bone_stitch_needle.tres` | 缝骨针 | 2/0 | 12 | R | armored-next +2 points, 2 |
| `ribwood_old_chest_cloak.tres` | 覆胸旧斗篷 | 2/2 | 10 | C | none |
| `ribwood_last_stand_strike.tres` | 末路重击 | 4/0 | 12 | R | none |
| `ribwood_white_horn_relic.tres` | 白角遗片 | 3/1 | 16 | E | none |
| `ribwood_sternum_plate.tres` | 胸骨护板 | 2/2 | 16 | E | next +2 armor, 1 |
| `ribwood_guardian_ember.tres` | 守护余烬 | 2/3 | 16 | E | none |

Use the exact descriptions from the design document (including `无额外效果。` and `此效果仅生效 X 次。`). Preserve tags, artwork paths, and IDs. For each changed rule resource, replace the external script resource reference with the new rule's actual generated `uid` and `path`, set its exported fields, and set `effective_count` on the subresource.

- [ ] **Step 4: Verify actual Resource loading and data contract**

Run:

```powershell
& $godot --headless --path . --script res://tests/ribwood_card_data_test.gd
```

Expected: exit code `0`; a passing preloaded test proves each `.tres` resolves the intended rule class rather than merely containing plausible text.

- [ ] **Step 5: Safely commit only intentional resource/data-test changes**

Inspect all resource lines and staged paths:

```powershell
git diff -- data/levels/ribwood/cards tests/ribwood_card_data_test.gd
git add data/levels/ribwood/cards/ribwood_guardian_root.tres data/levels/ribwood/cards/ribwood_rib_blade.tres data/levels/ribwood/cards/ribwood_old_tinder.tres data/levels/ribwood/cards/ribwood_folded_rib_shield.tres data/levels/ribwood/cards/ribwood_warm_marrow_flask.tres data/levels/ribwood/cards/ribwood_rib_nail.tres data/levels/ribwood/cards/ribwood_shield_fragment.tres data/levels/ribwood/cards/ribwood_amber_marrow_bottle.tres data/levels/ribwood/cards/ribwood_bone_armor_round_shield.tres data/levels/ribwood/cards/ribwood_ember_blade.tres data/levels/ribwood/cards/ribwood_warmth_charm.tres data/levels/ribwood/cards/ribwood_scar_bottle.tres data/levels/ribwood/cards/ribwood_grave_beetle.tres data/levels/ribwood/cards/ribwood_bone_stitch_needle.tres data/levels/ribwood/cards/ribwood_old_chest_cloak.tres data/levels/ribwood/cards/ribwood_last_stand_strike.tres data/levels/ribwood/cards/ribwood_white_horn_relic.tres data/levels/ribwood/cards/ribwood_sternum_plate.tres data/levels/ribwood/cards/ribwood_guardian_ember.tres tests/ribwood_card_data_test.gd
git diff --cached --check
git diff --cached --name-only
```

Commit only if the staged path list is exactly those files:

```powershell
git commit -m "feat(ribwood): refresh card pool data and copy"
```

## Task 4: Test actual Ribwood synergy behavior and balance integration

**Files:**
- Modify: `tests/ribwood_card_rules_test.gd`
- Modify: `tests/ribwood_combat_balance_test.gd`

**Interfaces:**
- Consumes: Task 2 rule classes loaded indirectly by Task 3 `.tres` resources and `CardChainRuleService.resolve_card_added()`.
- Produces: regression coverage proving actual player-obtainable cards trigger only in their intended placement positions and preserve the first-combat teaching threshold.

- [ ] **Step 1: Add actual-resource rule integration tests**

Preload `ribwood_bone_stitch_needle.tres`, `ribwood_ember_blade.tres`, `ribwood_warmth_charm.tres`, `ribwood_shield_fragment.tres`, and `ribwood_bone_armor_round_shield.tres`. Add these calls to `_run_tests()` in `ribwood_card_rules_test.gd`:

```gdscript
_test_bone_stitch_needle_requires_an_armored_next_card()
_test_ember_blade_rewards_only_the_qualifying_long_chain_head()
_test_warmth_charm_grants_limited_long_chain_head_armor()
_test_finite_ribwood_support_cards_exhaust_after_configured_uses()
```

Required exact assertions:

```gdscript
# Stitch Needle: armorless next card remains at base 1 point; armored next
# card gains 2 points; source records one use only for the successful case.
# Ember Blade: at chain size 4, head gains +2 points once; a later head does
# not gain points because effective_count is 1.
# Warmth Charm: at chain size 4, head gains +2 armor once; a later head does
# not gain armor.
# Shield Fragment: first next card gains +2 armor; second does not.
# Bone Armor Round Shield: first and second next cards each gain +2 armor;
# third does not.
```

- [ ] **Step 2: Run the actual-card rule integration test**

Run:

```powershell
& $godot --headless --path . --script res://tests/ribwood_card_rules_test.gd
```

Expected: exit code `0` after Task 3. A failure indicates a resource script UID/path, `effective_count`, sequence ordering, or data value mismatch.

- [ ] **Step 3: Preserve and expand the first-encounter balance proof**

Keep `_test_recommended_three_card_chain_kills_marrow_rat()` in `ribwood_combat_balance_test.gd`. Add explicit assertions before combat that the successful placement call returns `1` and that `tinder.current_points == 2`, then retain the existing post-combat assertions that the 4-HP rat dies through Tinder then Rib Blade while the Root retains 2 points.

- [ ] **Step 4: Run focused combat/balance regression tests**

Run:

```powershell
& $godot --headless --path . --script res://tests/ribwood_card_rules_test.gd
& $godot --headless --path . --script res://tests/ribwood_combat_balance_test.gd
& $godot --headless --path . --script res://tests/combatv2_service_test.gd
```

Expected: each exits `0`; no change to point-comparison combat behavior is needed for the card refresh.

- [ ] **Step 5: Commit test-only follow-up safely**

Review and commit only the two test files if their diff contains no unrelated changes:

```powershell
git add tests/ribwood_card_rules_test.gd tests/ribwood_combat_balance_test.gd
git diff --cached --check
git diff --cached --name-only
git commit -m "test(ribwood): cover refreshed card synergies"
```

## Task 5: Run affected game-data regressions and final validation

**Files:**
- Modify: `docs/design/2026-08-10-ribwood-card-effect-refresh-design.md` only if implementation reveals a genuine discrepancy from the approved design; otherwise no file change.

**Interfaces:**
- Consumes: all runtime rules, resources, and tests from Tasks 1–4.
- Produces: a checked implementation with no whitespace errors and no newly introduced Godot parser/resource loader errors.

- [ ] **Step 1: Run all directly affected data, rewards, and encounter tests**

Run:

```powershell
& $godot --headless --path . --script res://tests/ribwood_card_data_test.gd
& $godot --headless --path . --script res://tests/ribwood_card_rules_test.gd
& $godot --headless --path . --script res://tests/ribwood_combat_balance_test.gd
& $godot --headless --path . --script res://tests/ribwood_echo_data_test.gd
& $godot --headless --path . --script res://tests/ribwood_event_lib_test.gd
& $godot --headless --path . --script res://tests/starting_deck_data_test.gd
& $godot --headless --path . --script res://tests/encounter_reward_resolver_test.gd
```

Expected: every command exits `0`.

- [ ] **Step 2: Inspect final working-tree safety and formatting**

Run:

```powershell
git diff --check
git status --short
git diff -- scripts/combatv2/card/card_chain_rule_context.gd scripts/combatv2/card/rules data/levels/ribwood/cards tests/card_chain_rule_service_test.gd tests/ribwood_card_data_test.gd tests/ribwood_card_rules_test.gd tests/ribwood_combat_balance_test.gd
```

Expected: no whitespace errors. Treat pre-existing changes outside these paths as out of scope and leave them untouched.

- [ ] **Step 3: Verify the acceptance criteria manually against tests**

Confirm the following from the test output and resource inspection:

```text
1. All 19 cards match the approved point/armor/value/rarity/copy table.
2. Every special rule description names timing, target, numeric value, and finite count where applicable.
3. Each new CardRule consumes effective_count only after a real positive mutation.
4. Root -> Rib Blade -> Old Tinder defeats the 4-HP Marrow Rat without consuming the Root.
5. Bone Stitch Needle requires the direct next card to already have armor.
6. Ember Blade and Warmth Charm require a size-4-or-greater chain and operate on the newly placed head.
7. Existing affected combat, reward, event library, and starting deck tests pass.
```

- [ ] **Step 4: Report implementation state without touching unrelated changes**

Report exact created/modified files, test commands and outcomes, and any remaining unrelated unstaged files. Do not use `git reset`, `git clean`, or a broad checkout as cleanup.

## Plan Self-Review

- **Spec coverage:** Tasks 1–2 implement the three new `CardRule` types and proper count semantics. Task 3 implements all 19 approved card values, rarities, rules, and explicit text. Task 4 checks real-resource behavior and starter-chain balance. Task 5 checks that card-pool changes do not break event/reward/starting-deck consumers.
- **No complex systems added:** No task modifies combat resolution, curses/retreat, faith, maps, event generation, Boss pursuit, UI, or unrelated guide-card logic.
- **Type consistency:** All three new rules use the pre-existing `CardRule.execute_on_card_added(context: CardChainRuleContext) -> bool` hook. Their exported field names are consistently `bonus_points`, `armor`, and `minimum_chain_size`; resource tests assert those exact names.
- **Workspace safety:** Every proposed staging command explicitly lists files. No task uses a destructive git command or stages the whole working tree.
