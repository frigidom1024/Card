# Shop / ShopZone 市场重构实施计划

> 执行要求：每个生产变更先写失败测试，确认按预期失败，再做最小实现并运行通过。

**目标：** 在新 `Card`/`CardZone`/`DraggerLayer` 架构中完成独立可用的商店管理和拖拽购买闭环。

## Task 1：Card 精确绑定与拖拽更新

**文件：**
- 新建 `tests/card_instance_binding_test.gd`
- 修改 `scenes/card/card.gd`

步骤：
1. 测试 Card 可绑定/读取同一个 CardInstance，null 可清除。
2. 测试拖拽移动会通知 DraggerLayer 更新命中。
3. 运行测试确认因 API/通知缺失失败。
4. 添加绑定 API和 `update_drag` 调用。
5. 运行新测试及 `dragger_layer_test.gd`。

## Task 2：ShopZone 商品槽位与购买事务

**文件：**
- 新建 `tests/shop_zone_purchase_test.gd`
- 修改 `scripts/zone/shop_zone.gd`
- 必要时最小修改 `scenes/zone/shop_zone.tscn`

步骤：
1. 覆盖商品设置、替换、查询、布局和清理。
2. 覆盖无实例/验证失败时拒绝离开。
3. 覆盖拖拽失败恢复槽位与位置。
4. 覆盖目标提交成功后仅移除内部引用，并发出精确实例信号。
5. 运行 RED，再实现最小固定槽位与事务逻辑，运行 GREEN。
6. 回归 `card_zone_test.gd`、`dragger_layer_test.gd` 和 HandZone 相关测试。

## Task 3：RunCardService 精确实例注册

**文件：**
- 新建 `tests/run_card_service_existing_instance_test.gd`
- 修改 `scripts/game/run/run_card_service.gd`

步骤：
1. 测试登记现有 CardInstance 保持对象身份且不生成副本。
2. 测试 null、无 CardData 和重复登记处理。
3. 运行 RED。
4. 添加与旧 CardEntity 数组隔离的最小注册/查询 API。
5. 运行新测试与现有 `run_card_service_test.gd`。

## Task 4：Shop 管理、刷新、购买和拖拽层

**文件：**
- 新建 `tests/shop_scene_test.gd`
- 新建 `scripts/zone/shop.gd`
- 修改 `scenes/zone/shop.tscn`

步骤：
1. 测试场景脚本/节点路径和依赖校验。
2. 测试初次库存为绑定 CardInstance 的商品。
3. 测试 refresh 金币校验、扣款、全量替换及活动拖拽阻止。
4. 测试购买预校验、成功扣款、精确实例登记和单槽补货。
5. 测试 `set_drag_layer` 注销旧层、注册新层和重绑所有商品。
6. 运行 RED。
7. 实现 Shop、接入用户改名后的 `ShopTitle`/`Space`/`CostCoin` 节点并保留素材改动。
8. 运行 GREEN。

## Task 5：完整验证

1. 使用 Godot 脚本验证检查所有修改/新增 GDScript。
2. 运行所有新测试和相关回归测试。
3. 使用 Godot MCP 校验 `shop.tscn`、`shop_zone.tscn` 场景完整性。
4. 检查编辑器错误输出。
5. 审查 `git diff`，确认没有覆盖用户的 card/shop 场景和新素材修改。
6. 明确记录本阶段未替换旧 GameManager persistent_market 的边界。
