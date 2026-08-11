## local_authority.gd — 单机本地权威（T0005M13F05：P0 主要交付物，不是测试工具）
## fake_transport 环回 + 跑在客户端进程里的极简权威，只实现移动、扩张、边界对抗。
## 服务端规则（T0001M03F04 边界对抗）：
##   目标格=原汤 → 占领正常速率；敌方且对方不在充能 → 抢占；敌方且对方在充能 → 僵持；锅外跳过
## 输出：0x0C0 Snapshot(20Hz) · 0x0C1 TerritoryDelta(10Hz, 累积式) · 0x0C2 ScoreTick(1Hz)
## 上层（battle_root）无感知 —— 它就是"服务端"。

class_name LocalAuthority
extends Node

const TICK_S := 0.05
const P1_COLOR_INDEX := 0

var transport: FakeTransport = null
var grid := TerritoryGrid.new()
var players := {}                  # id → {pos_x, pos_y, vel_x, vel_y, aim, buttons, hp, flags, nickname}
var me_id: int = 1
## 默认拉满（调参面板上限 256）。64 时第一格要按 6.4 秒才翻，肉眼看不出在涨。
## 铺满得快没关系 —— 死亡溶解会把地盘不断打回原汤，10 分钟一直有得抢。
var expand_rate_fixed := 256
var tick: int = 0
var _tick_acc := 0.0
var _delta_accum := {}             # owner → Array[翻转记录 {tick, idx}]
var _last_delta_tick := 0
var _score_acc := 0.0
var _inside_cells := 0
var _seeding := false

var _match_start: Dictionary = {}

# ── 板子 / 窗口权威状态（D0001M03·M04，规则对齐 be/internal/sim/game.go）──────
var pallets: Array = []            # {id, pos:Vector2, state:0立着/1倒下, push_ms, by, hits}
var vaults: Array = []             # {id, pos:Vector2}
var walls: Array = []              # MapData 的 OBB 墙，供移动阻挡
var drops: Array = []              # {id, kind, pos:Vector2}
var drop_points: Array = []        # 固定坑位
var _drop_next_id := 0
var _drop_timer := 0
var _drop_first_done := false
var finished := false
const PLAYER_RADIUS_BASE := 0.5    # 轻装半径（体型随面积放大，见 _player_radius）
const PALLET_RADIUS := 0.55        # 倒下的板子作为圆形障碍

# KNOB（D0001，与 be/internal/sim/knob.go 同源；改数两边一起改）
const KNOB_INTERACT_RANGE := 1.5   # 交互范围（世界单位）
const KNOB_PALLET_PUSH_MS := 250
const KNOB_PALLET_STUN_MS := 800
const KNOB_PALLET_STUN_RANGE := 1.5
const KNOB_PALLET_BREAK_HITS := 3
## 基础伤害 40 × 攻击倍率。配合 HP 表：
##   小(10%)打小 36 → **3 刀**；大(35%)打小 54 → 2 刀
##   小打大 36 → 6 刀；大打大 54 → 4 刀
## 大的能秒小的但追不上（3.6 vs 7.0），小的要磨但机动 —— 博弈在这。
const KNOB_ATTACK_DAMAGE := 40
## 出手即承诺：命中后摇短，**挥空后摇长**。
## 没有挥空惩罚的话最优解永远是「一直挥」——那就是疯狗互点，不是刀战。
## 自动锁定下射程内必中，所以「挥空」= 射程外出手 → 玩家必须判断距离。
const KNOB_ATTACK_CD_MS := 250          # 命中后摇
const KNOB_ATTACK_WHIFF_MS := 700       # 挥空后摇（对方白得一个反打窗口）
## 出手即承诺：前摇几乎定身，后摇也跑不快。
## 这才是移速博弈的真正载体 —— 底速差只有 25%，但你一出手就慢到 0.3×，
## 所以「够不够得着」这个判断有了实实在在的代价，挥空要付出走不掉的风险。
const KNOB_WINDUP_MOVE_MULT := 0.30
const KNOB_RECOVER_MOVE_MULT := 0.50
const KNOB_ATTACK_WINDUP_MS := 200
## Bot 停下出手的距离 = 自己实际射程 × 这个系数。
## 不能用常量 —— 射程已经随体型变（1.8~3.2），写死 2.6 会让小形态 Bot
## 停在 2.6 却只够得着 2.0，永远挥空还白吃 700ms 长后摇（实测 968 tick 前摇 / 0 死亡）。
const BOT_ENGAGE_FACTOR := 0.75
const KNOB_ATTACK_ARC_DEG := 100.0     # 扇形半角 ±50°
# 击退初速，单位与移速同口径：定点 1/16 单位/**秒**。
# 按 decay 每 tick 递减，120 起步 / 每 tick -20 → 约 6 tick(0.3s) 推开 1.3 单位。
const KNOB_KNOCKBACK := 120
const KNOB_KNOCKBACK_DECAY := 20
const KNOB_HIT_STUN_MS := 250
const KNOB_RESPAWN_INVULN_MS := 1500
const KNOB_HEAVY_THRESHOLD := 3500     # 面积万分比，≥35% 过重（禁板子）
const KNOB_HEAVY_UNLOCK := 3000        # 滞回：≤30% 解锁
## ⚠️ 这里原本有「同一扇窗 8s 内翻第 3 次 → 落地硬直」的连翻惩罚
## （逃跑吧少年 / DBD 的防绕机制），已按合家欢定位去掉 —— 不惩罚玩家。
## 留下的风险：可能出现「绕着一个窗无限转圈，追的人永远抓不到」。
## P0 实测跑一局就知道会不会真发生；要加回来的话是一个计数器 + 一次 stun_ms 的事。
## 脱战回血：脱战 3s 后，只要在扩张就回血。
## 让「铺汤」从纯计分动作变成战术撤退 —— 打残了退回自己汤里边铺边回，
## 追击者进你地盘要冒被反打的风险（主场优势也一并有了）。
const KNOB_OUT_OF_COMBAT_TICKS := 60    # 3s @20Hz
## ⚠️ 单位是 HP/**秒**，不是 HP/tick。写成每 tick 8 点的话 20Hz = 160 HP/s，
## 玩家血永远满、Bot 怎么打都打不死（实测全场 0 死亡）。用累加器攒够 1 点再加。
const KNOB_REGEN_PER_SEC := 8
const RESPAWN_LADDER_MS := [3000, 5000, 8000]
const RESPAWN_SEED_CELLS := 8.0    # 复活种子圆盘半径（格）≈ 2.9%

## ── 道具（D0001M08）───────────────────────────────────────────────────────
## 位置**固定**、种类随机。全随机会让落后的人连「去哪抢」都不知道，
## 合家欢定位下那是挫败源；固定坑位才能形成「抢点」的博弈。
const KNOB_DROP_FIRST_TICKS := 600     # 首刷 30s @20Hz
const KNOB_DROP_INTERVAL_TICKS := 400  # 之后每 20s
const KNOB_DROP_PICK_RANGE := 1.0
const DROP_POINT_R := 6.5              # 坑位半径（锅心岛外一圈）
# 效果池
const DROP_RUNTIAN := 0                # 润甜：扩张 ×2.5
const DROP_SHIELD := 1                 # 护盾：吸收伤害
const DROP_SPEED := 2                  # 加速
const DROP_SLIM := 3                   # 瘦身：临时变轻（能翻窗、能下板）
const DROP_KINDS := 4
const KNOB_RUNTIAN_MS := 6000
const KNOB_RUNTIAN_MULT := 2.5
const KNOB_SHIELD_AMOUNT := 30
const KNOB_SHIELD_MS := 8000
const KNOB_SPEED_MS := 5000
const KNOB_SPEED_MULT := 1.35
const KNOB_SLIM_MS := 8000
const KNOB_SLIM_FACTOR := 0.6          # 属性计算时面积 ×0.6，地盘/计分不受影响

## 收官（D0001M05F02 / G0001M07）
const KNOB_MATCH_TICKS := 12000        # 10:00 @20Hz
## 提前结束阈值。原来 65%，但扩张拉满后 71 秒就会被触碰 ——
## 10 分钟的局根本走不完。85% 才配叫「一锅端了」，而且在死亡溶解的存在下
## 只有真碾压才够得到。（实测：65% → 71s 结束；85% → 打满全场）
const KNOB_EARLY_WIN_PERMYRIAD := 8500
const TICK_MS := 50                    # 20Hz


func begin_match(nickname: String, ingredient_id: int, bot_count: int = 3) -> void:
	grid = TerritoryGrid.new(96, 96)
	# me + bot_count 个 Bot（共 2~4 人），四角开局各 10% 地盘。
	# map_data.spawns 只有 4 个角，bot_count 越界会直接下标崩，先夹住。
	bot_count = clampi(bot_count, 1, 3)
	var player_count := 1 + bot_count
	players.clear()
	var map_data := MapData.build_map(1)
	_inside_cells = _count_inside()
	# 板子 / 窗口权威状态（表现层 battle_root 自己建 Node，这里只管规则）
	pallets.clear()
	for pl in map_data.pallets:
		pallets.append({"id": pl.id, "pos": Vector2(pl.x, pl.y), "state": 0,
			"push_ms": 0, "by": 0, "hits": 0})
	vaults.clear()
	for v in map_data.vaults:
		vaults.append({"id": v.id, "pos": Vector2(v.x, v.y)})
	walls = map_data.walls
	# 道具坑位：锅心岛外一圈，4 重对称（对四个玩家公平）
	drops.clear()
	drop_points.clear()
	_drop_next_id = 0
	_drop_timer = 0
	_drop_first_done = false
	for k in range(4):
		var ta := deg_to_rad(45.0 + 90.0 * k)
		drop_points.append(MapData.CENTER + Vector2(cos(ta), sin(ta)) * DROP_POINT_R)
	for k in range(player_count):
		var pid := k + 1
		var spawn: Dictionary = map_data.spawns[k]
		players[pid] = {
			"pos_x": Fixed.world_to_fixed(spawn.x),
			"pos_y": Fixed.world_to_fixed(spawn.y),
			"vel_x": 0, "vel_y": 0,
			"aim": Fixed.angle_to_uint16(spawn.angle),
			"buttons": 0, "hp": Sim.hp_max_for_area(1000),   # 初始 10% → 100
			"flags": 0,
			"nickname": nickname if k == 0 else "Bot%d" % k,
			"ingredient": ingredient_id if k == 0 else _bot_ingredient(ingredient_id, k),
			"expand_r": 0,
			# ── 战斗 / 交互状态（D0001M03·M04，规则对齐 be/internal/sim/game.go）──
			"stun_ms": 0,          # 眩晕剩余（板子砸中 / 被击退）
			"vault_ms": 0,         # 翻窗剩余，>0 期间不可移动/攻击
			"vault_id": -1,
			"atk_cd_ms": 0,        # 挥击冷却
			"atk_windup_ms": 0,    # 前摇（结束瞬间判定命中）
			"windup_target": 0,
			"invuln_ms": 0,        # 复活无敌
			"dead": false,
			"respawn_ms": 0,
			"death_count": 0,
			"kills": 0,
			"combat_ms": 0, "regen_acc": 0,
			"kb_x": 0, "kb_y": 0,  # 击退速度（定点 1/16，每 tick 衰减）
			"runtian_ms": 0, "shield": 0, "shield_ms": 0,
			"speed_ms": 0, "slim_ms": 0,
			"spawn_x": Fixed.world_to_fixed(spawn.x),
			"spawn_y": Fixed.world_to_fixed(spawn.y),
		}
		# 开局 10% 圆盘（半径 ≈ 15.2 格，T0001M03F01）
		_seeding = true
		_seed_area(pid, spawn.x, spawn.y, 15.2)
		_seeding = false
	me_id = 1
	_match_start = {
		"map_id": 1, "start_tick": 0, "stew_ticks": 3600,   # D0001：3:00
		"grid_w": 96, "grid_h": 96, "player_count": player_count, "players": [],
	}
	for k in range(player_count):
		var spawn: Dictionary = map_data.spawns[k]
		_match_start.players.append({
			"player_id": k + 1,
			"ingredient_id": players[k + 1].ingredient,
			"nickname": players[k + 1].nickname,
			"spawn_x": Fixed.world_to_fixed(spawn.x),
			"spawn_y": Fixed.world_to_fixed(spawn.y),
		})


## Bot 食材：从玩家没选的三种里按顺序挑，避免和玩家撞色。
## 原来是 `ingredient_id if k == 0 else k`，玩家一旦选了紫菜/玉米/茄子
## 就会和对应的 Bot 同色同名，场上分不清谁是谁。
func _bot_ingredient(player_ing: int, k: int) -> int:
	var pool: Array = []
	for i in range(4):
		if i != player_ing:
			pool.append(i)
	return pool[(k - 1) % pool.size()]


func mock_match_start() -> Dictionary:
	return _match_start


func mock_me_id() -> int:
	return me_id


## 开局关键帧（0x0C3 格式）：从本地权威的 authGrid 行优先 RLE 生成（供客户端初始化）
func mock_keyframe() -> PackedByteArray:
	var runs := []
	var prev := -1
	var length := 0
	for i in range(grid.auth_grid.size()):
		var v: int = grid.auth_grid[i]
		if v == prev:
			length += 1
		else:
			if prev != -1:
				runs.append({"length": length, "owner": prev})
			prev = v
			length = 1
	if length > 0:
		runs.append({"length": length, "owner": prev})
	return codec.encode_territory_keyframe(0, runs)


func attach_transport(t: FakeTransport) -> void:
	transport = t


func _count_inside() -> int:
	var n := 0
	for i in range(grid.auth_grid.size()):
		if grid.auth_grid[i] != TerritoryGrid.OUTSIDE:
			n += 1
	return n


func _seed_area(pid: int, wx: float, wy: float, radius_cells: float) -> void:
	## 出生圆盘：世界坐标 → 格。
	## radius_cells 的单位是**格**（T0001M03F01 的「半径 ≈ 15.2 格」），不是世界单位。
	## 原来这里又乘了一次 2（世界单位→格的换算），半径翻倍 → 每人开局 21% 而不是 10%，
	## 四人合计吃掉 85% 的锅，原汤几乎不剩，「按住铺开」根本铺不动。
	var cx := Fixed.fixed_to_grid(Fixed.world_to_fixed(wx))
	var cy := Fixed.fixed_to_grid(Fixed.world_to_fixed(wy))
	var rr := int(radius_cells)
	for y in range(maxi(0, cy - rr), mini(95, cy + rr)):
		for x in range(maxi(0, cx - rr), mini(95, cx + rr)):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= rr * rr and grid.auth_grid[y * 96 + x] == TerritoryGrid.BROTH:
				grid.auth_grid[y * 96 + x] = pid
				_flip(pid, y * 96 + x)


func _flip(owner: int, idx: int) -> void:
	if _seeding:
		return   # 开局由 Keyframe 初始化，不产生增量
	if not _delta_accum.has(owner):
		_delta_accum[owner] = []
	_delta_accum[owner].append({"tick": tick, "idx": idx})


func set_expand_rate_fixed(v: int) -> void:
	expand_rate_fixed = v


# ══ 客户端消息入口（fake_transport 调用）═══════════════════════════════════

func handle_client_message(msg_id: int, body: PackedByteArray) -> void:
	if msg_id == MsgIds.PLAYER_INPUT:
		var r := ByteReader.new(body)
		## 头部 clientTick u32 · inputSeq u16 · frameCount u8 = 7B
		if body.size() < 7:
			return
		r.read_u32()                       # clientTick
		var seq := r.read_u16()            # inputSeq（最新帧）
		var frame_count := r.read_u8()
		# 最新帧在前（T0001M02F04）
		var frames := []
		for i in range(frame_count):
			frames.append({
				"move_x": r.read_i8(), "move_y": r.read_i8(),
				"aim": r.read_u16(), "buttons": r.read_u8(),
			})
		var last_snap_tick := r.read_u32()
		var last_terr_tick := r.read_u32()
		if frames.size() > 0:
			var f: Dictionary = frames[0]
			var p: Dictionary = players[me_id]
			p.move_x = f.move_x
			p.move_y = f.move_y
			p.aim = f.aim
			p.buttons = f.buttons
			p.input_seq = seq
			p.last_terr_tick = last_terr_tick
		_trim_delta_accum(last_terr_tick)


func _trim_delta_accum(ack_tick: int) -> void:
	## 累积式增量：客户端 ACK 之后裁剪（T0001M03F06）
	for owner in _delta_accum.keys():
		var list: Array = _delta_accum[owner]
		var keep: Array = []
		for rec in list:
			if rec.tick > ack_tick:
				keep.append(rec)
		if keep.is_empty():
			_delta_accum.erase(owner)
		else:
			_delta_accum[owner] = keep


# ══ 权威 tick（20Hz）═══════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if transport == null:
		return
	_tick_acc += delta
	while _tick_acc >= TICK_S:
		_tick_acc -= TICK_S
		tick += 1
		_authority_tick()


## Tick 顺序对齐服务端（T0004M04 / be sim.Game.Step）：
##   计时器 → Bot AI → 交互（翻窗/推板）→ 移动 → 扩张 → 战斗 → 输出
## 「扩张必须在移动之后」「战斗用上一 tick 的质量属性」是硬约束（BE0000M05）。
func _authority_tick() -> void:
	_step_timers()
	_bot_ai()
	_step_interact()
	# 移动（充能时减速 0.45×，D0001M05；眩晕/翻窗/死亡不能动）
	for pid in players:
		var p: Dictionary = players[pid]
		if _immobile(p):
			p.vel_x = 0
			p.vel_y = 0
			_apply_knockback(pid)
			continue
		var mult := 1.0
		if p.buttons & MsgIds.BUTTON_CHARGE != 0:
			mult = 0.45                                  # 充能时减速（D0001M05）
		if p.atk_windup_ms > 0:
			mult = minf(mult, KNOB_WINDUP_MOVE_MULT)     # 前摇：几乎定身
		elif p.atk_cd_ms > 0:
			mult = minf(mult, KNOB_RECOVER_MOVE_MULT)    # 后摇：跑不快
		_apply_movement(pid, mult)
		_apply_knockback(pid)
	# 扩张（边界对抗，T0001M03F04）
	for pid in players:
		var p: Dictionary = players[pid]
		if p.dead or p.invuln_ms > 0:
			continue
		if p.buttons & MsgIds.BUTTON_CHARGE != 0:
			_expand_authority(pid)
	_step_combat()
	_step_items()
	_step_regen()
	_step_endgame()
	if finished:
		return
	# 输出
	_emit_snapshot()
	if tick % 5 == 0:               # 10Hz 地盘帧
		_emit_delta()
	if tick % 20 == 0:              # 1Hz 面积
		_emit_score()


## 眩晕 / 翻窗 / 死亡 期间不可自主移动（击退仍然生效）
func _immobile(p: Dictionary) -> bool:
	return p.dead or p.stun_ms > 0 or p.vault_ms > 0


# ══ 计时器 ═════════════════════════════════════════════════════════════════

func _step_timers() -> void:
	for pid in players:
		var p: Dictionary = players[pid]
		p.stun_ms = maxi(0, p.stun_ms - TICK_MS)
		p.atk_cd_ms = maxi(0, p.atk_cd_ms - TICK_MS)
		p.invuln_ms = maxi(0, p.invuln_ms - TICK_MS)
		p.runtian_ms = maxi(0, p.runtian_ms - TICK_MS)
		p.speed_ms = maxi(0, p.speed_ms - TICK_MS)
		p.slim_ms = maxi(0, p.slim_ms - TICK_MS)
		p.shield_ms = maxi(0, p.shield_ms - TICK_MS)
		if p.shield_ms == 0:
			p.shield = 0
		# 翻窗完成
		if p.vault_ms > 0:
			p.vault_ms = maxi(0, p.vault_ms - TICK_MS)
			if p.vault_ms == 0:
				_teleport_through_vault(pid)
				_emit_event(MsgIds.VAULT_END, PackedByteArray([pid, maxi(0, p.vault_id)]))
				p.vault_id = -1
		# 复活
		if p.dead:
			p.respawn_ms = maxi(0, p.respawn_ms - TICK_MS)
			if p.respawn_ms == 0:
				_respawn(pid)
	# 板子倒下动画计时
	for pl in pallets:
		if pl.push_ms > 0:
			pl.push_ms = maxi(0, pl.push_ms - TICK_MS)


# ══ Bot AI：直线追最近的玩家（V0001M02F01 第 6 条）═══════════════════════════

func _bot_ai() -> void:
	## P0 追逐 Bot：锁最近的活人直线追；追到范围内就挥击；
	## 没人可追（都死了）就朝锅心走，顺手充能占地盘。
	for pid in players:
		if pid == me_id:
			continue
		var p: Dictionary = players[pid]
		p.buttons = 0
		if _immobile(p):
			p.move_x = 0
			p.move_y = 0
			continue
		var me_pos := Vector2(float(p.pos_x) / 64.0, float(p.pos_y) / 64.0)
		var target := _nearest_alive(pid)
		if target <= 0:
			# 无目标：朝锅心走 + 充能
			var to_center := MapData.CENTER - me_pos
			if to_center.length() > 1.0:
				var d := to_center.normalized()
				p.move_x = int(d.x * 60.0)
				p.move_y = int(d.y * 60.0)
			else:
				p.move_x = 0
				p.move_y = 0
				p.buttons |= MsgIds.BUTTON_CHARGE
			continue
		var t: Dictionary = players[target]
		var t_pos := Vector2(float(t.pos_x) / 64.0, float(t.pos_y) / 64.0)
		var to_t := t_pos - me_pos
		var dist := to_t.length()
		p.aim = Fixed.angle_to_uint16(to_t.angle())
		# 充能 / 追击轮换。
		# 只按距离判「远了就不追」不行 —— 开局四角相距 24 单位，任何合理的
		# 距离阈值都等于永不追击，V0001M02F01 第 6 条的追逐 Bot 就不存在了。
		# 轮换能同时给出两种压力：别人也在铺（Q1）+ 有人来抓你（Q2）。
		# 用 tick 取模、每个 Bot 错开相位，保持确定性（不许 randi）。
		# 老家被啃了就先回防（优先于追击相位）
		var area := _area_permyriad(pid)
		p["peak_area"] = maxi(p.get("peak_area", area), area)
		var under_siege := area < int(p.peak_area * BOT_DEFEND_RATIO)
		if under_siege or not _bot_hunting(pid):
			p.move_x = 0
			p.move_y = 0
			p.buttons |= MsgIds.BUTTON_CHARGE
			continue
		if dist > 0.01:
			var dir := to_t / dist
			p.move_x = int(dir.x * 100.0)
			p.move_y = int(dir.y * 100.0)
		# 进入自己的有效射程才出手（挥空要吃长后摇，Bot 也一样）
		if dist <= Sim.attack_range_for_area(_effective_area(pid)) * BOT_ENGAGE_FACTOR:
			p.buttons |= MsgIds.BUTTON_ACTION
			p.move_x = 0
			p.move_y = 0


## Bot 行为轮换：充能 BOT_CHARGE_TICKS → 追击 BOT_HUNT_TICKS，各 Bot 相位错开。
## 纯 tick 取模，无随机 —— 本地权威也要保持可复现。
## 实测 8s/10s 的轮换下，10 分钟全场只死 1 次 —— 死亡溶解这个 sink 等于没开。
## 提高追击占比让冲突真的发生。
const BOT_CHARGE_TICKS := 120      # 6s 铺地盘
const BOT_HUNT_TICKS := 240        # 12s 追人
## 防守本能：地盘被啃掉一截就回来补，不管现在是不是追击相位。
## 没有这条，Bot 出门追人时老家被白拿 —— 实测一个全程按住扩张的玩家
## 125 秒就能铺到 82%，滚雪球没人拦。
const BOT_DEFEND_RATIO := 0.7
const BOT_CYCLE := BOT_CHARGE_TICKS + BOT_HUNT_TICKS


func _bot_hunting(pid: int) -> bool:
	var phase := (tick + (pid - 2) * (BOT_CYCLE / 3)) % BOT_CYCLE
	return phase >= BOT_CHARGE_TICKS


func _nearest_alive(from_pid: int) -> int:
	var p: Dictionary = players[from_pid]
	var from_pos := Vector2(float(p.pos_x) / 64.0, float(p.pos_y) / 64.0)
	var best := 0
	var best_d := 1e9
	for pid in players:
		if pid == from_pid:
			continue
		var o: Dictionary = players[pid]
		if o.dead or o.invuln_ms > 0:
			continue
		var d := from_pos.distance_to(Vector2(float(o.pos_x) / 64.0, float(o.pos_y) / 64.0))
		if d < best_d:
			best_d = d
			best = pid
	return best


# ══ 交互：翻窗 / 推板（V0001M02F01 第 4·5 条）════════════════════════════════

func _step_interact() -> void:
	for pid in players:
		var p: Dictionary = players[pid]
		if p.dead or p.vault_ms > 0 or p.stun_ms > 0 or p.atk_windup_ms > 0:
			continue
		# 万能键（BUTTON_ACTION）：一个键三种结果，权威按距离分发。
		# 旧的 BUTTON_INTERACT 仍兼容（老客户端 / 触屏那套还没重做）。
		if p.buttons & (MsgIds.BUTTON_ACTION | MsgIds.BUTTON_INTERACT) == 0:
			continue
		var pos := Vector2(float(p.pos_x) / 64.0, float(p.pos_y) / 64.0)
		# 就近判定，不是「先翻窗、翻不了再推板」——
		# 地图上窗和板最近只隔 0.3 单位（A0001M09 的灶台组团），
		# 「窗优先」会让板子永远按不出来。
		var v_i := _nearest_vault(pos)
		var p_i := _nearest_pallet(pos)
		var v_d: float = pos.distance_to(vaults[v_i].pos) if v_i >= 0 else 1e9
		var p_d: float = pos.distance_to(pallets[p_i].pos) if p_i >= 0 else 1e9
		if v_i < 0 and p_i < 0:
			p["action_to_attack"] = true    # 附近没窗没板 → 这次按键当挥击用
			continue
		if v_d <= p_d:
			_do_vault(pid, v_i)
		else:
			_do_push_pallet(pid, p_i)


## 范围内最近的窗（没有返回 -1）
func _nearest_vault(pos: Vector2) -> int:
	var best := -1
	var best_d := KNOB_INTERACT_RANGE
	for i in range(vaults.size()):
		var d: float = pos.distance_to(vaults[i].pos)
		if d <= best_d:
			best_d = d
			best = i
	return best


## 范围内最近的、还立着的板（没有返回 -1）
func _nearest_pallet(pos: Vector2) -> int:
	var best := -1
	var best_d := KNOB_INTERACT_RANGE
	for i in range(pallets.size()):
		if pallets[i].state != 0:
			continue
		var d: float = pos.distance_to(pallets[i].pos)
		if d <= best_d:
			best_d = d
			best = i
	return best


## 翻窗：耗时随面积（D0001M03F01，Sim.vault_time_for_area）。期间不可移动/攻击，可被打。
func _do_vault(pid: int, idx: int) -> void:
	var p: Dictionary = players[pid]
	var area := _effective_area(pid)
	p.vault_ms = int(Sim.vault_time_for_area(area) * 1000.0)
	p.vault_id = vaults[idx].id
	p.vel_x = 0
	p.vel_y = 0
	_emit_event(MsgIds.VAULT_START, PackedByteArray([pid, p.vault_id]))


## 翻窗完成 → 穿到窗的另一侧（沿「进入方向」推过去，简化：跨过窗口 1.2 单位）
func _teleport_through_vault(pid: int) -> void:
	var p: Dictionary = players[pid]
	var v := _vault_by_id(p.vault_id)
	if v.is_empty():
		return
	var pos := Vector2(float(p.pos_x) / 64.0, float(p.pos_y) / 64.0)
	var through: Vector2 = v.pos + (v.pos - pos).normalized() * 1.2
	if MapData.inside_pot(through):
		p.pos_x = Fixed.world_to_fixed(through.x)
		p.pos_y = Fixed.world_to_fixed(through.y)


func _vault_by_id(vid: int) -> Dictionary:
	for v in vaults:
		if v.id == vid:
			return v
	return {}


## 推板：过重（≥35% 面积）下不了板（D0001M04）。板子倒下 → 障碍 + 范围眩晕。
func _do_push_pallet(pid: int, idx: int) -> void:
	if _is_heavy(pid):
		return
	var pl: Dictionary = pallets[idx]
	pl.state = 1
	pl.push_ms = KNOB_PALLET_PUSH_MS
	pl.by = pid
	# 范围眩晕：板子砸下来，圈内除推板者外全眩晕
	for other_id in players:
		if other_id == pid:
			continue
		var o: Dictionary = players[other_id]
		if o.dead or o.invuln_ms > 0:
			continue
		var o_pos := Vector2(float(o.pos_x) / 64.0, float(o.pos_y) / 64.0)
		if o_pos.distance_to(pl.pos) <= KNOB_PALLET_STUN_RANGE:
			o.stun_ms = maxi(o.stun_ms, KNOB_PALLET_STUN_MS)
	_emit_event(MsgIds.PALLET_DOWN, PackedByteArray([pl.id, pid]))


## 过重判定（滞回：≥35% 锁，≤30% 解锁，D0001M04）
func _is_heavy(pid: int) -> bool:
	var p: Dictionary = players[pid]
	var area := _effective_area(pid)
	var locked: bool = p.get("heavy_lock", false)
	if area >= KNOB_HEAVY_THRESHOLD:
		locked = true
	elif area <= KNOB_HEAVY_UNLOCK:
		locked = false
	p["heavy_lock"] = locked
	return locked


# ══ 战斗：挥击 → 前摇 → 命中 → 伤害 + 击退（V0001M02F01 第 7 条）═════════════

func _step_combat() -> void:
	for pid in players:
		var p: Dictionary = players[pid]
		if p.dead:
			continue
		# 前摇中：走完就判命中
		if p.atk_windup_ms > 0:
			p.atk_windup_ms = maxi(0, p.atk_windup_ms - TICK_MS)
			if p.atk_windup_ms == 0:
				var hit := _apply_hit(pid, p.windup_target)
				p.atk_cd_ms = KNOB_ATTACK_CD_MS if hit else KNOB_ATTACK_WHIFF_MS
			continue
		# 只有「万能键落空（附近没窗没板）」才是挥击。
		# Bot 直接用 BUTTON_ACTION，走 _step_interact 时也会置 action_to_attack。
		if not p.get("action_to_attack", false):
			continue
		p["action_to_attack"] = false
		# 冷却中 / 充能中 / 眩晕 / 翻窗 / 无敌 都不能挥
		if p.atk_cd_ms > 0 or p.invuln_ms > 0 or _immobile(p):
			continue
		if p.buttons & MsgIds.BUTTON_CHARGE != 0:
			continue
		p.atk_windup_ms = KNOB_ATTACK_WINDUP_MS
		# 自动锁定（元气骑士式）：权威自己挑最近的对手并把角色转过去，
		# **不信客户端传来的 aim** —— 那个值只用于表现。
		p.windup_target = _nearest_target(pid)
		if p.windup_target > 0:
			var t: Dictionary = players[p.windup_target]
			var dir := Vector2(float(t.pos_x - p.pos_x), float(t.pos_y - p.pos_y))
			if dir.length_squared() > 0.0:
				p.aim = Fixed.angle_to_uint16(dir.angle())


## 自动锁定：射程内最近的活对手。
## 锁定后角色会转过去，所以不再需要扇形判定（转过去之后扇形恒成立）；
## 扇形只保留在 _apply_hit 的复核里，用来顺带打到同方向的其他人。
func _nearest_target(pid: int) -> int:
	var p: Dictionary = players[pid]
	var pos := Vector2(float(p.pos_x) / 64.0, float(p.pos_y) / 64.0)
	var best := 0
	var best_d := Sim.attack_range_for_area(_effective_area(pid))
	for other_id in players:
		if other_id == pid:
			continue
		var o: Dictionary = players[other_id]
		if o.dead or o.invuln_ms > 0:
			continue
		var o_pos := Vector2(float(o.pos_x) / 64.0, float(o.pos_y) / 64.0)
		var d := pos.distance_to(o_pos)
		if d > best_d:
			continue
		best_d = d
		best = other_id
	return best


## 返回是否真的打中（决定后摇长短）
func _apply_hit(attacker_id: int, target_id: int) -> bool:
	if target_id <= 0 or not players.has(target_id):
		return false
	var a: Dictionary = players[attacker_id]
	var t: Dictionary = players[target_id]
	if t.dead or t.invuln_ms > 0:
		return false
	var a_pos := Vector2(float(a.pos_x) / 64.0, float(a.pos_y) / 64.0)
	var t_pos := Vector2(float(t.pos_x) / 64.0, float(t.pos_y) / 64.0)
	# 前摇结束复核距离
	if a_pos.distance_to(t_pos) > Sim.attack_range_for_area(_effective_area(attacker_id)):
		return false   # 射程外 → 挥空，走长后摇
	var dmg := int(round(KNOB_ATTACK_DAMAGE * Sim.attack_mult_for_area(_effective_area(attacker_id))))
	if t.get("shield", 0) > 0:
		var absorbed: int = mini(t.shield, dmg)
		t.shield -= absorbed
		dmg -= absorbed
	t.hp = maxi(0, t.hp - dmg)
	t.stun_ms = maxi(t.stun_ms, KNOB_HIT_STUN_MS)
	# 双方都进战斗状态（脱战计时重置）
	a["combat_ms"] = KNOB_OUT_OF_COMBAT_TICKS * TICK_MS
	t["combat_ms"] = KNOB_OUT_OF_COMBAT_TICKS * TICK_MS
	# 击退：沿攻击者→目标方向，重的推不动（击退 ÷ 质量系数）
	var dir := (t_pos - a_pos).normalized() if a_pos.distance_to(t_pos) > 0.001 else Vector2.RIGHT
	var mass_factor := 1.0 + float(_area_permyriad(target_id)) / 6500.0
	t.kb_x = int(dir.x * KNOB_KNOCKBACK / mass_factor)
	t.kb_y = int(dir.y * KNOB_KNOCKBACK / mass_factor)
	if t.hp <= 0:
		t.dead = true
		t.death_count += 1
		a["kills"] = a.get("kills", 0) + 1
		var idx: int = mini(t.death_count - 1, RESPAWN_LADDER_MS.size() - 1)
		t.respawn_ms = RESPAWN_LADDER_MS[idx]
		t.stun_ms = 0
		t.kb_x = 0
		t.kb_y = 0
		_dissolve_territory(target_id)
		_emit_event(MsgIds.PLAYER_DIED, PackedByteArray([target_id, attacker_id]))
	return true


## 死亡溶解（G0001）：把死者的地盘整片化回原汤，谁都能抢。
## 这条是「围攻领先者」的收益结构 —— 打死最肥的那个，等于给全场分蛋糕。
## 一直没接，所以之前打死人没有任何战略意义。
func _dissolve_territory(pid: int) -> void:
	for i in range(grid.auth_grid.size()):
		if grid.auth_grid[i] == pid:
			grid.auth_grid[i] = TerritoryGrid.BROTH
			grid.dirty[i] = 1
			_flip(TerritoryGrid.BROTH, i)
	# frontier 失效，下次充能重建
	grid._expand_r.erase(pid)
	grid._frontier.erase(pid)
	grid._in_frontier.erase(pid)


## 脱战回血：脱战 3s 且正在扩张 → 回血。上限随体型（Sim.hp_max_for_area）。
func _step_regen() -> void:
	for pid in players:
		var p: Dictionary = players[pid]
		p["combat_ms"] = maxi(0, p.get("combat_ms", 0) - TICK_MS)
		if p.dead or p.combat_ms > 0:
			continue
		if p.buttons & MsgIds.BUTTON_CHARGE == 0:
			continue
		var cap := Sim.hp_max_for_area(_effective_area(pid))
		# 累加器：每 tick 攒 KNOB_REGEN_PER_SEC 点，攒满 TICK_HZ 才落 1 HP
		p["regen_acc"] = p.get("regen_acc", 0) + KNOB_REGEN_PER_SEC
		while p.regen_acc >= Fixed.TICK_HZ:
			p.regen_acc -= Fixed.TICK_HZ
			p.hp = mini(cap, p.hp + 1)


## 击退位移（每 tick 衰减，与自主移动叠加）
func _apply_knockback(pid: int) -> void:
	var p: Dictionary = players[pid]
	if p.kb_x == 0 and p.kb_y == 0:
		return
	var nx: int = p.pos_x + p.kb_x * Fixed.POS_SCALE / (Fixed.VEL_SCALE * Fixed.TICK_HZ)
	var ny: int = p.pos_y + p.kb_y * Fixed.POS_SCALE / (Fixed.VEL_SCALE * Fixed.TICK_HZ)
	var world := Vector2(float(nx) / Fixed.POS_SCALE, float(ny) / Fixed.POS_SCALE)
	# 走和自主移动同一条阻挡结算：只夹锅壁的话会被打穿墙、或者被塞进墙里，
	# 下一帧 _apply_movement 再把人从随机一侧弹出来。
	world = _resolve_obstacles(world, pid)
	p.pos_x = Fixed.world_to_fixed(world.x)
	p.pos_y = Fixed.world_to_fixed(world.y)
	p.kb_x = _decay(p.kb_x)
	p.kb_y = _decay(p.kb_y)


func _decay(v: int) -> int:
	if v > 0:
		return maxi(0, v - KNOB_KNOCKBACK_DECAY)
	return mini(0, v + KNOB_KNOCKBACK_DECAY)


func _respawn(pid: int) -> void:
	var p: Dictionary = players[pid]
	p.dead = false
	p.hp = Sim.hp_max_for_area(_effective_area(pid))
	p.pos_x = p.spawn_x
	p.pos_y = p.spawn_y
	p.invuln_ms = KNOB_RESPAWN_INVULN_MS
	p.stun_ms = 0
	p.vault_ms = 0
	p.atk_windup_ms = 0
	p.kb_x = 0
	p.kb_y = 0
	# ⚠️ 必须重新播种一小片地盘。
	# 膨胀是从「自己已有地盘的边界」出发的（_build_authority_frontier），
	# 死亡溶解清空之后 frontier 永远建不起来 —— 实测全场 4 人一起卡在 0%，
	# 锅空了 8 分钟。复活 = 重新下锅，脚下得有汤才铺得开。
	# 比开局(15.2 格 ≈10%)小得多，死一次要重新铺，这本身就是惩罚。
	var sp := Vector2(float(p.spawn_x) / 64.0, float(p.spawn_y) / 64.0)
	_seed_area(pid, sp.x, sp.y, RESPAWN_SEED_CELLS)
	grid._expand_r.erase(pid)
	grid._frontier.erase(pid)
	grid._in_frontier.erase(pid)
	_emit_event(MsgIds.PLAYER_RESPAWN, PackedByteArray([pid]))


# ══ 道具（D0001M08）══════════════════════════════════════════════════════

func _step_items() -> void:
	# 刷新：首刷 30s，此后每 20s 一个
	if not _drop_first_done:
		_drop_timer += 1
		if _drop_timer >= KNOB_DROP_FIRST_TICKS:
			_drop_first_done = true
			_drop_timer = 0
			_spawn_drop()
	else:
		_drop_timer += 1
		if _drop_timer >= KNOB_DROP_INTERVAL_TICKS:
			_drop_timer = 0
			_spawn_drop()
	# 拾取
	for pid in players:
		var p: Dictionary = players[pid]
		if p.dead:
			continue
		var pos := Vector2(float(p.pos_x) / 64.0, float(p.pos_y) / 64.0)
		for i in range(drops.size() - 1, -1, -1):
			var d: Dictionary = drops[i]
			if pos.distance_to(d.pos) > KNOB_DROP_PICK_RANGE:
				continue
			_apply_drop(pid, d.kind)
			_emit_event(MsgIds.DROP_TAKEN, PackedByteArray([d.id, pid]))
			drops.remove_at(i)


## 挑一个空坑位刷一个随机种类。
## 用 tick 派生的 LCG 而不是 randi —— 本地权威也要可复现（BE0000M05 第 3 条）。
func _spawn_drop() -> void:
	var free_idx: Array = []
	for i in range(drop_points.size()):
		var used := false
		for d in drops:
			if d.pos.distance_to(drop_points[i]) < 0.1:
				used = true
				break
		if not used:
			free_idx.append(i)
	if free_idx.is_empty():
		return
	var r1 := _det_rand(tick)
	var r2 := _det_rand(tick + 7919)
	var slot: int = free_idx[r1 % free_idx.size()]
	var kind := r2 % DROP_KINDS
	_drop_next_id = (_drop_next_id + 1) & 0xFF
	var pos: Vector2 = drop_points[slot]
	drops.append({"id": _drop_next_id, "kind": kind, "pos": pos})
	var w := ByteWriter.new(6)
	w.write_u8(_drop_next_id)
	w.write_u8(kind)
	w.write_u16(Fixed.world_to_fixed(pos.x))
	w.write_u16(Fixed.world_to_fixed(pos.y))
	_emit_event(MsgIds.DROP_SPAWN, w.data())


# ══ 收官 ═══════════════════════════════════════════════════════════════════

## 时间到 或 有人到 65% → 结算。
## 本地权威原来根本不结束对局，所以单机模式永远看不到结算屏。
func _step_endgame() -> void:
	if finished:
		return
	var early := false
	for pid in players:
		if _area_permyriad(pid) >= KNOB_EARLY_WIN_PERMYRIAD:
			early = true
			break
	if not early and tick < KNOB_MATCH_TICKS:
		return
	finished = true
	# 排名只看地盘面积；击杀只展示不参与排名（G0001M07）
	# 人数由 begin_match 的 bot_count 决定（2~4 人），不能再写死 4 个
	var order: Array = players.keys()
	order.sort_custom(func(a, b): return _area_permyriad(a) > _area_permyriad(b))
	var w := ByteWriter.new(1 + order.size() * 5)
	w.write_u8(order.size())
	for i in range(order.size()):
		var pid: int = order[i]
		w.write_u8(pid)
		w.write_u8(i + 1)
		w.write_u16(_area_permyriad(pid))
		w.write_u8(players[pid].get("kills", 0))
	transport.inject(MsgIds.CH_RELIABLE_ORDERED, MsgIds.MATCH_END, w.data())


func _det_rand(seed_v: int) -> int:
	return absi((seed_v * 1103515245 + 12345) >> 8)


func _apply_drop(pid: int, kind: int) -> void:
	var p: Dictionary = players[pid]
	match kind:
		DROP_RUNTIAN:
			p.runtian_ms = KNOB_RUNTIAN_MS
		DROP_SHIELD:
			p.shield = KNOB_SHIELD_AMOUNT
			p.shield_ms = KNOB_SHIELD_MS
		DROP_SPEED:
			p.speed_ms = KNOB_SPEED_MS
		DROP_SLIM:
			p.slim_ms = KNOB_SLIM_MS


## 属性计算用的「有效面积」：瘦身道具让你临时变轻（能翻窗、能下板），
## 但**不影响地盘面积和计分** —— 那是 _area_permyriad。
func _effective_area(pid: int) -> int:
	var a := _area_permyriad(pid)
	if players[pid].get("slim_ms", 0) > 0:
		a = int(a * KNOB_SLIM_FACTOR)
	return a


func _emit_event(msg_id: int, body: PackedByteArray) -> void:
	if transport != null:
		transport.inject(MsgIds.CH_RELIABLE_UNORDERED, msg_id, body)


func _apply_movement(pid: int, speed_mult: float) -> void:
	var p: Dictionary = players[pid]
	var area := _effective_area(pid)
	var base_speed := Sim.speed_for_area(area)
	if p.get("speed_ms", 0) > 0:
		speed_mult *= KNOB_SPEED_MULT
	var speed := int(base_speed * speed_mult)
	var vel := Fixed.dir_to_velocity(p.get("move_x", 0), p.get("move_y", 0), speed)
	# 与 Sim.step 同一口径：速度是 单位/秒，除 TICK_HZ 才是每 tick 位移
	var nx: int = p.pos_x + vel.x * Fixed.POS_SCALE / (Fixed.VEL_SCALE * Fixed.TICK_HZ)
	var ny: int = p.pos_y + vel.y * Fixed.POS_SCALE / (Fixed.VEL_SCALE * Fixed.TICK_HZ)
	var world := Vector2(float(nx) / Fixed.POS_SCALE, float(ny) / Fixed.POS_SCALE)
	world = _resolve_obstacles(world, pid)
	nx = Fixed.world_to_fixed(world.x)
	ny = Fixed.world_to_fixed(world.y)
	p.pos_x = nx
	p.pos_y = ny
	p.vel_x = vel.x
	p.vel_y = vel.y


## 阻挡结算：锅壁 → 墙（OBB）→ 倒下的板子（圆）。翻窗中不吃墙（正在穿过去）。
func _resolve_obstacles(world: Vector2, pid: int) -> Vector2:
	var p: Dictionary = players[pid]
	# 锅壁（圆形汤锅）
	if not MapData.inside_pot(world):
		world = MapData.CENTER + (world - MapData.CENTER).limit_length(MapData.POT_RADIUS - 0.3)
	if p.vault_ms > 0:
		return world
	var r := _player_radius(pid)
	for w in walls:
		world = Sim.resolve_wall(world, r, w)
	for pl in pallets:
		if pl.state == 1:
			world = Sim.resolve_circle(world, r, pl.pos, PALLET_RADIUS)
	return world


## 体型半径：跟面积走（A0001M08F02 的三档直径 ÷2）
func _player_radius(pid: int) -> float:
	return Sim.size_for_area(_effective_area(pid)) * 0.5


## 权威扩张（服务端规则，与客户端预测同构但允许抢占）
func _expand_authority(pid: int) -> void:
	var p: Dictionary = players[pid]
	if not grid._expand_r.has(pid):
		grid._expand_r[pid] = 0
		grid._frontier[pid] = []
		grid._in_frontier[pid] = {}
		_build_authority_frontier(pid)
	var rate := expand_rate_fixed
	if p.get("runtian_ms", 0) > 0:
		rate = int(rate * KNOB_RUNTIAN_MULT)      # 润甜（D0001M08）
	grid._expand_r[pid] += Fixed.expand_rate_to_r_inc(rate)
	var r: int = grid._expand_r[pid]
	var heap: Array = grid._frontier[pid]
	var seen: Dictionary = grid._in_frontier[pid]
	# 僵持格：本 tick 不推进，但要保留 dist 重回 frontier。
	# 不能原地 push 回去 —— dist 不变会被 while 立刻再弹出，死循环。
	# 攒到本 tick 走完再放回（对应服务端的 blocked[4][]uint32，见 be AGENTS.md）。
	var blocked: Array = []
	while heap.size() > 0:
		var top: Dictionary = heap[0]
		if top.dist > r:
			break
		heap.remove_at(0)
		seen.erase(top.cell)
		var cell: int = top.cell
		var cur: int = grid.auth_grid[cell]
		if cur == pid:
			# 已经是自己的格（别人抢过又被抢回来）：不重复计数，但要继续往外推
			_push_authority_neighbors(pid, cell, top.dist, seen)
			continue
		if cur == TerritoryGrid.BROTH or (cur >= 1 and cur <= 4):
			# 原汤 → 占领；敌方 → 对方不在充能则抢占，在充能则僵持
			if cur >= 1 and cur <= 4:
				var enemy: Dictionary = players.get(cur, {})
				if enemy.get("buttons", 0) & MsgIds.BUTTON_CHARGE != 0:
					blocked.append(top)
					continue
			grid.auth_grid[cell] = pid
			grid.dirty[cell] = 1
			_flip(pid, cell)
			_push_authority_neighbors(pid, cell, top.dist, seen)
		# 锅外：跳过
	# 僵持格放回 frontier，保留原 dist（下个 tick 对方松手就能推进）
	for b in blocked:
		grid._push_into(pid, b.cell % 96, b.cell / 96, b.dist, seen)


func _build_authority_frontier(pid: int) -> void:
	var seen: Dictionary = grid._in_frontier[pid]
	for y in range(96):
		for x in range(96):
			var idx := y * 96 + x
			if grid.auth_grid[idx] != pid:
				continue
			var boundary := false
			for nb in grid._neighbor_offsets():
				var nx: int = x + nb.x
				var ny: int = y + nb.y
				if not grid.in_bounds(nx, ny):
					continue
				if grid.auth_grid[ny * 96 + nx] != pid:
					boundary = true
					break
			if boundary:
				# 同 TerritoryGrid._build_frontier：压外邻，不压自己的格
				for nb2 in grid._neighbor_offsets():
					var bx: int = x + nb2.x
					var by: int = y + nb2.y
					if not grid.in_bounds(bx, by):
						continue
					if grid.auth_grid[by * 96 + bx] == pid:
						continue
					grid._push_into(pid, bx, by, Fixed.geodesic_dist(nb2.x, nb2.y), seen)


## base_dist 累加（同 TerritoryGrid._push_neighbors 的说明）
func _push_authority_neighbors(pid: int, cell: int, base_dist: int, seen: Dictionary) -> void:
	var x := cell % 96
	var y := cell / 96
	for nb in grid._neighbor_offsets():
		var nx: int = x + nb.x
		var ny: int = y + nb.y
		if not grid.in_bounds(nx, ny):
			continue
		var nidx: int = ny * 96 + nx
		if grid.auth_grid[nidx] == pid or seen.has(nidx):
			continue
		grid._push_into(pid, nx, ny, base_dist + Fixed.geodesic_dist(nb.x, nb.y), seen)


func _area_permyriad(pid: int) -> int:
	var n := grid.count_owner(pid)
	return int(round(float(n) / float(maxi(1, _inside_cells)) * 10000.0))


# ══ 下行输出 ═══════════════════════════════════════════════════════════════

func _emit_snapshot() -> void:
	var w := ByteWriter.new(72)
	w.write_u32(tick)
	w.write_u16(_last_input_seq())
	w.write_u8(players.size())
	for pid in players:                    # 人数可变（2~4），插入序即 1..N
		var p: Dictionary = players[pid]
		var flags := 0
		if p.buttons & MsgIds.BUTTON_CHARGE != 0:
			flags |= MsgIds.FLAG_CHARGING
		if p.vault_ms > 0:
			flags |= MsgIds.FLAG_VAULTING
		if p.dead:
			flags |= MsgIds.FLAG_DEAD
		if p.invuln_ms > 0:
			flags |= MsgIds.FLAG_INVULN
		if p.atk_windup_ms > 0:
			flags |= MsgIds.FLAG_WINDUP
		if _is_heavy(pid):
			flags |= MsgIds.FLAG_OVERWEIGHT
		w.write_u8(pid)
		w.write_u16(p.pos_x)
		w.write_u16(p.pos_y)
		w.write_i8(p.vel_x)
		w.write_i8(p.vel_y)
		w.write_u16(p.aim)
		w.write_u16(_area_permyriad(pid))   # mass = 面积万分比（T0001M02F05）
		w.write_u8(flags)
		w.write_u8(p.hp)
		# 攻击冷却剩余（单位 10ms，0~2.55s）。多这一字节是为了让**对手的**冷却条
		# 也能显示 —— 刀战博弈的核心信息就是「他现在能不能还手」。
		# 每玩家由此变成 14B，正好回到 T0001M02F05 文档原本写的 14 B/player。
		w.write_u8(clampi(int(p.atk_cd_ms / 10), 0, 255))
	transport.inject(MsgIds.CH_UNRELIABLE_UNORDERED, MsgIds.SNAPSHOT, w.data())


func _last_input_seq() -> int:
	return players[me_id].get("input_seq", 0)


func _emit_delta() -> void:
	## 按 owner 分组、组内 cellIndex 升序差值 varint（T0001M03F06）
	var w := ByteWriter.new(72)
	w.write_u32(tick)
	w.write_u32(_last_delta_tick)
	var owners := _delta_accum.keys()
	owners.sort()
	w.write_u8(owners.size())
	for owner in owners:
		var recs: Array = _delta_accum[owner]
		var cells := PackedInt32Array()
		for rec in recs:
			cells.append(rec.idx)
		cells.sort()
		# 去重（同格多 tick 翻转只发最新归属）
		var uniq := PackedInt32Array()
		for c in cells:
			if uniq.size() == 0 or uniq[uniq.size() - 1] != c:
				uniq.append(c)
		w.write_u8(owner)
		w.write_u16(uniq.size())
		var prev := 0
		for c in uniq:
			w.write_varint(c - prev)
			prev = c
	_last_delta_tick = tick
	transport.inject(MsgIds.CH_UNRELIABLE_UNORDERED, MsgIds.TERRITORY_DELTA, w.data())


func _emit_score() -> void:
	var w := ByteWriter.new(12)
	w.write_u32(tick)
	# 0x0C2 是**定长 4 槽**（codec.decode_score_tick 要求 body ≥ 12B）。
	# 不满 4 人时缺席位写 0（_area_permyriad 对不存在的 pid 返回 0），
	# 不能按实际人数缩短，否则整包被 drop、面积条彻底不动。
	for pid in range(1, 5):
		w.write_u16(_area_permyriad(pid))
	transport.inject(MsgIds.CH_UNRELIABLE_UNORDERED, MsgIds.SCORE_TICK, w.data())
