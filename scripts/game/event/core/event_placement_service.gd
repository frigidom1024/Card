class_name EventPlacementService
extends RefCounted

## 事件放置服务
##
## 负责：
## - 为运行时事件查找 BoardEventZone 中的合法格子
## - 创建 BoardEvent 视图并通过 Board 提交事件挂载
## - 保持放置失败时 EventInstance.origin 的原子恢复
##
## 不负责：
## - 管理事件集合与空间索引
## - 处理事件触发、悬停或结算业务
## - 管理卡牌棋盘空间
##
## 使用方式：
## 调用 place_initial_events()、place_event_instance() 或
## place_event_instance_in_cells()，并传入已组合 BoardEventZone 的 Board。
##
## 依赖：
## EventLib：创建事件数据与 BoardEvent 视图。
## Board：提交事件业务操作。
## BoardEventZone：提供事件网格空间查询。


func place_initial_events(
	event_lib: EventLib,
	board: Board,
	rng: RandomNumberGenerator = null
) -> Array[EventInstance]:
	var placed: Array[EventInstance] = []
	if event_lib == null or board == null or board.event_zone == null:
		return placed
	var random := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		random.randomize()
	for instance in event_lib.generate_event_datas():
		if place_event_instance(instance, event_lib, board, random):
			placed.append(instance)
		elif instance != null and instance.template != null:
			push_warning("No board space remains for event: %s" % instance.template.event_id)
	return placed


## Attaches a supplied runtime event at one randomly chosen valid map origin.
func place_event_instance(
	instance: EventInstance,
	event_lib: EventLib,
	board: Board,
	rng: RandomNumberGenerator = null
) -> bool:
	if (
		instance == null
		or instance.template == null
		or event_lib == null
		or board == null
		or board.event_zone == null
	):
		return false
	var event_zone: BoardEventZone = board.event_zone
	var candidates := _get_valid_origins(instance, event_zone)
	if candidates.is_empty():
		return false
	var random := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		random.randomize()
	instance.origin = candidates[random.randi_range(0, candidates.size() - 1)]
	var event_node := event_lib.create_event_scene(instance, event_zone.cell_size)
	if event_node != null and board.attach_event(event_node):
		return true
	if event_node != null:
		event_node.queue_free()
	instance.origin = Vector2i(-1, -1)
	return false


func _get_valid_origins(
	instance: EventInstance,
	event_zone: BoardEventZone
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	if instance == null or instance.template == null or event_zone == null:
		return candidates
	var event_size := instance.get_size()
	for x in maxi(0, event_zone.width - event_size.x + 1):
		for y in maxi(0, event_zone.height - event_size.y + 1):
			var origin := Vector2i(x, y)
			instance.origin = origin
			if event_zone.can_attach_event(instance):
				candidates.append(origin)
	instance.origin = Vector2i(-1, -1)
	return candidates


## Attaches a supplied runtime event only inside cells revealed by the current transaction.
func place_event_instance_in_cells(
	instance: EventInstance,
	event_lib: EventLib,
	board: Board,
	allowed_cells: Array[Vector2i],
	rng: RandomNumberGenerator = null
) -> bool:
	if (
		instance == null
		or instance.template == null
		or event_lib == null
		or board == null
		or board.event_zone == null
	):
		return false
	var event_zone: BoardEventZone = board.event_zone
	var allowed: Dictionary[Vector2i, bool] = {}
	for cell in allowed_cells:
		allowed[cell] = true
	var candidates: Array[Vector2i] = []
	var event_size := instance.get_size()
	for x in range(event_zone.width - event_size.x + 1):
		for y in range(event_zone.height - event_size.y + 1):
			var origin := Vector2i(x, y)
			var footprint := event_zone.get_event_cells(origin, event_size)
			var contained := true
			for cell in footprint:
				if not allowed.has(cell):
					contained = false
					break
			if not contained:
				continue
			instance.origin = origin
			if event_zone.can_attach_event(instance):
				candidates.append(origin)
	if candidates.is_empty():
		instance.origin = Vector2i(-1, -1)
		return false
	var random := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		random.randomize()
	instance.origin = candidates[random.randi_range(0, candidates.size() - 1)]
	var event_node := event_lib.create_event_scene(instance, event_zone.cell_size)
	if event_node != null and board.attach_event(event_node):
		return true
	if event_node != null:
		event_node.queue_free()
	instance.origin = Vector2i(-1, -1)
	return false
