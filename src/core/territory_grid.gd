## territory_grid.gd — TerritoryField 双网格（T0005M07，核心）
## 关键裁定（M07F03）：authGrid 只由 0x0C1/0x0C3/0x042 写；predOverlay 只由本地预测扩张写。
## 回传的 lastRecvTerritoryTick 只反映 authGrid，与预测无关（写错会被踢下线，T0001M08）。
## 预测扩张只吃 authGrid == 原汤 的格（M07F04：争议边界不预测）。
## 纯 GDScript，不 extends Node（可无头单测，M07F03 两条 Gherkin AC 做成自动化测试）。

class_name TerritoryGrid
extends RefCounted

const BROTH := 0        # 原汤（中性）
const OUTSIDE := 15     # 锅外
const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4

var grid_w := Fixed.GRID
var grid_h := Fixed.GRID

# ── 双网格（M07F01）────────────────────────────────────────────────────────
var auth_grid := PackedByteArray()     # 9216 B，权威归属（0/1..4/15）
var pred_owner := PackedByteArray()    # 9216 B，预测占领（0 = 无预测）
var pred_tick := PackedInt32Array()    # 9216 × 4B，预测发生 tick
var dirty := PackedByteArray()         # 渲染漫开动画的 dirty 标记（1 = 需要 150ms 渐变）

# ── 预测扩张状态（每玩家）───────────────────────────────────────────────────
var _expand_r := {}                    # player_id → R（定点 1/1024 格）
var _frontier := {}                    # player_id → Array[{dist, cell}]
var _in_frontier := {}                 # player_id → Dictionary[cell → true]（去重）
var _expand_rate_fixed := 64           # D0001：expandRate Q22.10 = 64
var _me_id := 0

# ── ACK 纪律（M07F02 / 唯一合法来源）────────────────────────────────────────
var last_auth_tick := 0                # 只由实际应用的 0x0C1/0x0C3/0x042 写入
var last_snapshot_tick := 0            # 只由实际应用的 0x0C0 写入

# 诊断
var predicted_revert_count := 0


func _init(w: int = Fixed.GRID, h: int = Fixed.GRID) -> void:
	grid_w = w
	grid_h = h
	var n := w * h
	auth_grid.resize(n)
	pred_owner.resize(n)
	pred_tick.resize(n)
	dirty.resize(n)
	# 默认全锅外，然后初始化锅形（圆内 = 原汤）
	for i in range(n):
		auth_grid[i] = OUTSIDE
	var cx := w / 2
	var cy := h / 2
	var r := mini(cx, cy) - 1          # 锅内半径（格）
	for y in range(h):
		for x in range(w):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r * r:
				auth_grid[y * w + x] = BROTH


func cell_index(x: int, y: int) -> int:
	return y * grid_w + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < grid_w and y >= 0 and y < grid_h


func owner_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return OUTSIDE
	return auth_grid[y * grid_w + x]


func owner_at_index(idx: int) -> int:
	return auth_grid[idx]


func render_owner_at(idx: int) -> int:
	## 渲染用归属：authGrid 叠加存活的 predOverlay（M07F03）
	if pred_owner[idx] != 0:
		return pred_owner[idx]
	return auth_grid[idx]


func set_me(player_id: int) -> void:
	_me_id = player_id


func get_me() -> int:
	return _me_id


# ══ 权威写入（M07F02：唯一三个入口）════════════════════════════════════════

## 0x0C3 TerritoryKeyframe：整表覆盖 + 清空全部预测（M07F02）
func apply_keyframe(server_tick: int, runs: Array) -> void:
	auth_grid.fill(OUTSIDE)
	var idx := 0
	for run in runs:
		var length: int = run.length
		var owner: int = run.owner
		for i in range(length):
			if idx < auth_grid.size():
				auth_grid[idx] = owner
				dirty[idx] = 1
				idx += 1
			else:
				break
	# 覆盖后清空全部预测
	clear_all_prediction()
	last_auth_tick = server_tick


## 0x0C1 TerritoryDelta：累积式增量应用（M07F02）
func apply_delta(server_tick: int, groups: Array) -> void:
	for g in groups:
		var owner: int = g.owner
		var cells: PackedInt32Array = g.cells
		for idx in cells:
			if idx >= 0 and idx < auth_grid.size():
				auth_grid[idx] = owner
				dirty[idx] = 1
	last_auth_tick = server_tick
	_validate_prediction(server_tick)


## 0x042 FullState 后的 Keyframe 已整表覆盖；此方法供重连清零（M09F04）
func reset_all() -> void:
	auth_grid.fill(OUTSIDE)
	clear_all_prediction()
	last_auth_tick = 0


func clear_all_prediction() -> void:
	pred_owner.fill(0)
	pred_tick.fill(0)
	_expand_r.clear()
	_frontier.clear()
	_in_frontier.clear()


# ══ 预测校验（M07F03，每次收到地盘帧后必须做）══════════════════════════════

func _validate_prediction(server_tick: int) -> void:
	## 对每个预测格：predTick <= server_tick 时服务端已处理过该时刻——
	##   认了（authGrid == predOwner）→ 收编，撤掉覆盖
	##   没认 → 回退 + 由表现层播「被顶回来」收缩动效
	for i in range(pred_owner.size()):
		var po := pred_owner[i]
		if po == 0:
			continue
		if pred_tick[i] <= server_tick:
			if auth_grid[i] != po:
				predicted_revert_count += 1
				# 回退：渲染归属回到 authGrid（此处只清数据，动效由 renderer 订阅 dirty）
				dirty[i] = 1
			pred_owner[i] = 0
			pred_tick[i] = 0


# ══ 本地预测扩张（M07F04）══════════════════════════════════════════════════

## 开始/继续预测扩张（按住时每 tick 调一次）
func expand_tick(player_id: int, input_tick: int) -> void:
	if not _expand_r.has(player_id):
		# 初始化：从玩家当前地盘边界建立 frontier
		_expand_r[player_id] = 0
		_frontier[player_id] = []
		_in_frontier[player_id] = {}
		_build_frontier(player_id)
	_expand_r[player_id] += Fixed.expand_rate_to_r_inc(_expand_rate_fixed)
	var r: int = _expand_r[player_id]
	var heap: Array = _frontier[player_id]
	var seen: Dictionary = _in_frontier[player_id]
	var rinc := 0
	while heap.size() > 0:
		var top: Dictionary = heap[0]
		if top.dist > r:
			break
		heap.remove_at(0)
		seen.erase(top.cell)
		var cell: int = top.cell
		if auth_grid[cell] == BROTH:          # ← 只吃原汤（M07F04）
			pred_owner[cell] = player_id
			pred_tick[cell] = input_tick
			dirty[cell] = 1
			rinc += 1
			_push_neighbors(player_id, cell, seen)
		# 敌方/锅外：停在这里，等服务端裁决


func stop_expansion(player_id: int) -> void:
	## 松手：R 停增，frontier 保留（M07F04：下次接着推）
	pass


func set_expand_rate(expand_rate_fixed: int) -> void:
	_expand_rate_fixed = expand_rate_fixed


func _build_frontier(player_id: int) -> void:
	## 从该玩家地盘的边界格出发（边界 = 紧邻非己方地盘的己方格）
	var seen: Dictionary = _in_frontier[player_id]
	for y in range(grid_h):
		for x in range(grid_w):
			var idx := y * grid_w + x
			if auth_grid[idx] != player_id:
				continue
			var is_boundary := false
			for nb in _neighbor_offsets():
				var nx := x + nb.x
				var ny := y + nb.y
				if not in_bounds(nx, ny):
					continue
				var nv := auth_grid[ny * grid_w + nx]
				if nv != player_id:
					is_boundary = true
					break
			if is_boundary:
				# 边界外邻的 dist = 到边界的距离（0 起步），推进时按邻接累加
				_push_into(player_id, x, y, 0, seen)


func _push_neighbors(player_id: int, cell: int, seen: Dictionary) -> void:
	var x := cell % grid_w
	var y := cell / grid_w
	for nb in _neighbor_offsets():
		var nx := x + nb.x
		var ny := y + nb.y
		if not in_bounds(nx, ny):
			continue
		var nidx := ny * grid_w + nx
		if pred_owner[nidx] == player_id or seen.has(nidx):
			continue
		var dist := Fixed.geodesic_dist(nb.x, nb.y)
		_push_into(player_id, nx, ny, dist, seen)


func _push_into(player_id: int, x: int, y: int, dist: int, seen: Dictionary) -> void:
	var idx := y * grid_w + x
	if seen.has(idx):
		return
	seen[idx] = true
	var heap: Array = _frontier[player_id]
	# 小顶堆插入（量小：每 tick 4~5 格，线性插入足够；保持有序便于 pop 最小值）
	var item := {"dist": dist, "cell": idx}
	var pos := 0
	while pos < heap.size() and heap[pos].dist <= dist:
		pos += 1
	heap.insert(pos, item)


func _neighbor_offsets() -> Array:
	return [{"x": 1, "y": 0}, {"x": -1, "y": 0}, {"x": 0, "y": 1}, {"x": 0, "y": -1},
		{"x": 1, "y": 1}, {"x": 1, "y": -1}, {"x": -1, "y": 1}, {"x": -1, "y": -1}]


# ══ 查询 ══════════════════════════════════════════════════════════════════

func count_owner(owner: int) -> int:
	var n := 0
	for i in range(auth_grid.size()):
		if auth_grid[i] == owner:
			n += 1
	return n


func count_area_permyriad(owner: int, total_inside: int) -> int:
	var n := count_owner(owner)
	return int(round(float(n) / float(maxi(1, total_inside)) * 10000.0))


## 世界坐标（定点）所在格的渲染归属
func owner_at_fixed(fx: int, fy: int) -> int:
	var x := Fixed.fixed_to_grid(fx)
	var y := Fixed.fixed_to_grid(fy)
	if not in_bounds(x, y):
		return OUTSIDE
	return render_owner_at(y * grid_w + x)
