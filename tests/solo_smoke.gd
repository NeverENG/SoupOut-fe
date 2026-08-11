## solo_smoke.gd — 单机权威冒烟测试（无头）
## 跑法：godot --headless --path . -s res://tests/solo_smoke.gd
##
## 验的是「玩法逻辑真的接上了」，不是「代码能编译」：
## 扩张 / Bot 追人 / 挥击伤害 / 板子眩晕 / 翻窗耗时随质量 / 墙体阻挡。

extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run("扩张：按住能长地盘", _t_expand)
	_run("Bot：直线追最近的活人", _t_bot_chase)
	_run("万能键落空 → 自动锁定挥击 + 击退", _t_attack)
	_run("板子：推倒后范围眩晕 + 变障碍", _t_pallet)
	_run("翻窗：耗时随面积增长", _t_vault)
	_run("墙体：OBB 阻挡不让穿", _t_wall)
	_run("地图：出生点远离窗板 + 数量对账", _t_map)
	_run("道具：刷新 + 拾取 + 效果生效", _t_drops)
	_run("协议：ScoreTick 编解码字段顺序一致", _t_score_tick)
	_run("战斗博弈：3 刀打死小的 + 挥空长后摇", _t_combat_gameplay)
	_run("移速：大小差距收窄 + 出手位移惩罚", _t_move_tradeoff)
	_run("协议：Snapshot 带攻击冷却（每玩家 14B）", _t_snapshot_cd)
	_run("死亡溶解：地盘化回原汤", _t_dissolve)
	_run("脱战回血：扩张时恢复", _t_regen)
	print("==== 冒烟完成：%d 项，失败 %d ====" % [_pass + _fail, _fail])
	quit(1 if _fail > 0 else 0)


func _run(name: String, fn: Callable) -> void:
	var ok: bool = fn.call()
	if ok:
		_pass += 1
		print("[PASS] ", name)
	else:
		_fail += 1
		print("[FAIL] ", name)


## 建一个已开局的本地权威（transport 用 FakeTransport，事件丢弃即可）
func _make_authority() -> LocalAuthority:
	var la := LocalAuthority.new()
	var fake := FakeTransport.new()
	la.attach_transport(fake)
	la.begin_match("test", 0)
	return la


func _tick(la: LocalAuthority, n: int) -> void:
	for i in range(n):
		la.tick += 1
		la._authority_tick()


func _pos(la: LocalAuthority, pid: int) -> Vector2:
	var p: Dictionary = la.players[pid]
	return Vector2(float(p.pos_x) / 64.0, float(p.pos_y) / 64.0)


# ══ 用例 ══════════════════════════════════════════════════════════════════

func _t_expand() -> bool:
	var la := _make_authority()
	# 摘掉 Bot：现在它们会真的把站着不动的玩家打死，
	# 死亡溶解会把地盘清零（实测 851 → 0），这条用例就测不到扩张本身了。
	for pid in [2, 3, 4]:
		la.players.erase(pid)
	var before := la._area_permyriad(1)
	la.players[1].buttons = MsgIds.BUTTON_CHARGE
	_tick(la, 200)         # 10 秒（expandRate 已默认拉满 256）
	var after := la._area_permyriad(1)
	if after <= before:
		print("  面积没涨：%d → %d" % [before, after])
		return false
	return true


func _t_bot_chase() -> bool:
	var la := _make_authority()
	# 把 Bot2 挪到玩家附近（6 单位内，追逐阈值 8 以内）
	var me := _pos(la, 1)
	la.players[2].pos_x = Fixed.world_to_fixed(me.x + 5.0)
	la.players[2].pos_y = Fixed.world_to_fixed(me.y)
	# Bot 是「充能 8s / 追击 10s」轮换的，得把 tick 拨到追击相位再测，
	# 否则量到的是它在原地铺地盘（_bot_hunting）。
	la.tick = LocalAuthority.BOT_CHARGE_TICKS
	var d0 := _pos(la, 2).distance_to(_pos(la, 1))
	_tick(la, 20)          # 1 秒
	var d1 := _pos(la, 2).distance_to(_pos(la, 1))
	if d1 >= d0:
		print("  Bot 没靠近：%.2f → %.2f" % [d0, d1])
		return false
	return true


func _t_attack() -> bool:
	var la := _make_authority()
	# 万能键是情境键：附近有窗/板就会被翻窗/推板消化。
	# 这条用例只验挥击那条分支，所以先清掉场上的窗和板。
	# （顺带暴露一个地图问题：出生点距离最近的窗只有 1.3 单位，
	#   真实对局里开局按键会误翻窗 —— 地图重做时出生点要挪开。）
	la.vaults.clear()
	la.pallets.clear()
	var me := _pos(la, 1)
	# 目标放正前方 1.5 单位（在 2.4 射程和 ±50° 扇形内）
	la.players[2].pos_x = Fixed.world_to_fixed(me.x + 1.5)
	la.players[2].pos_y = Fixed.world_to_fixed(me.y)
	la.players[1].aim = Fixed.angle_to_uint16(0.0)
	var hp0: int = la.players[2].hp
	var x0 := _pos(la, 2).x
	la.players[1].buttons = MsgIds.BUTTON_ACTION
	_tick(la, 1)           # 起前摇
	la.players[1].buttons = 0
	_tick(la, 6)           # 前摇 150ms = 3 tick，多跑几帧看击退
	var hp1: int = la.players[2].hp
	if hp1 >= hp0:
		print("  没掉血：%d → %d" % [hp0, hp1])
		return false
	if _pos(la, 2).x <= x0:
		print("  没被击退：x %.3f → %.3f" % [x0, _pos(la, 2).x])
		return false
	return true


func _t_pallet() -> bool:
	var la := _make_authority()
	var pl: Dictionary = la.pallets[0]
	# 玩家站到板边，Bot2 站在眩晕圈内
	la.players[1].pos_x = Fixed.world_to_fixed(pl.pos.x + 0.5)
	la.players[1].pos_y = Fixed.world_to_fixed(pl.pos.y)
	la.players[2].pos_x = Fixed.world_to_fixed(pl.pos.x - 0.8)
	la.players[2].pos_y = Fixed.world_to_fixed(pl.pos.y)
	la.players[1].buttons = MsgIds.BUTTON_INTERACT
	_tick(la, 1)
	if la.pallets[0].state != 1:
		print("  板子没倒下")
		return false
	if la.players[2].stun_ms <= 0:
		print("  圈内没被眩晕")
		return false
	# 倒下的板子应该挡住移动：从板心正上方往板心推，会被推开
	var probe := Sim.resolve_circle(pl.pos, 0.5, pl.pos, la.PALLET_RADIUS)
	if probe.distance_to(pl.pos) < 0.5:
		print("  板子没有变成障碍")
		return false
	return true


func _t_vault() -> bool:
	var la := _make_authority()
	var v: Dictionary = la.vaults[0]
	la.players[1].pos_x = Fixed.world_to_fixed(v.pos.x)
	la.players[1].pos_y = Fixed.world_to_fixed(v.pos.y)
	la.players[1].buttons = MsgIds.BUTTON_INTERACT
	_tick(la, 1)
	var light_ms: int = la.players[1].vault_ms
	if light_ms <= 0:
		print("  没进入翻窗态")
		return false
	# 翻窗期间不可移动
	la.players[1].buttons = 0
	la.players[1].move_x = 100
	var before := _pos(la, 1)
	_tick(la, 2)
	if _pos(la, 1).distance_to(before) > 0.01:
		print("  翻窗中还能走")
		return false
	# 耗时应随面积增长（LUT：10%→400ms，50%→1400ms）
	var t_light := Sim.vault_time_for_area(1000)
	var t_heavy := Sim.vault_time_for_area(5000)
	if t_heavy <= t_light:
		print("  重装翻窗没有更慢：%.2f vs %.2f" % [t_light, t_heavy])
		return false
	return true


func _t_wall() -> bool:
	var la := _make_authority()
	var w: Dictionary = la.walls[0]
	var center := Vector2(w.x, w.y)
	# 从墙心出发解算：半径 0.5 的圆必须被推到墙外
	var out := Sim.resolve_wall(center, 0.5, w)
	var half: Vector2 = w.half_extent
	var facing: Vector2 = w.facing
	var perp := Vector2(-facing.y, facing.x)
	var rel := out - center
	var lx := absf(rel.dot(facing))
	var ly := absf(rel.dot(perp))
	if lx < half.x + 0.49 and ly < half.y + 0.49:
		print("  墙心没被弹出：local=(%.3f, %.3f) half=(%.3f, %.3f)" % [lx, ly, half.x, half.y])
		return false
	# 墙外的点不该被动
	var far := center + facing * (half.x + 5.0)
	if Sim.resolve_wall(far, 0.5, w).distance_to(far) > 0.001:
		print("  墙外的点被误推")
		return false
	return true


## 地图对账：数量 + 出生点安全距离
func _t_map() -> bool:
	var m := MapData.build_map(1)
	# A0001M09 原定 13/12/8，已按「地图要更复杂」的要求打破。
	# 这里只卡下限 + 4 重对称（四个玩家必须公平），不再钉死具体数字。
	if m.walls.size() < 30 or m.vaults.size() < 12 or m.pallets.size() < 8:
		print("  地形太稀疏：墙%d 窗%d 板%d" % [m.walls.size(), m.vaults.size(), m.pallets.size()])
		return false
	if m.walls.size() % 4 != 1 or m.vaults.size() % 4 != 0 or m.pallets.size() % 4 != 0:
		print("  不是 4 重对称：墙%d（应 4n+1，锅心菱形算 1）窗%d 板%d"
			% [m.walls.size(), m.vaults.size(), m.pallets.size()])
		return false
	# 出生点不能卡在墙里
	for sp in m.spawns:
		var sp_pos := Vector2(sp.x, sp.y)
		for w in m.walls:
			if Sim.resolve_wall(sp_pos, 0.5, w).distance_to(sp_pos) > 0.001:
				print("  P%d 出生点卡在墙里" % sp.player_id)
				return false
	# 出生点离最近的窗/板必须 > 交互范围，否则开局按万能键会误触
	for sp in m.spawns:
		var p := Vector2(sp.x, sp.y)
		var d := 1.0e9
		for v in m.vaults:
			d = minf(d, p.distance_to(Vector2(v.x, v.y)))
		for pl in m.pallets:
			d = minf(d, p.distance_to(Vector2(pl.x, pl.y)))
		if d < 3.0:
			print("  P%d 出生点距最近窗/板只有 %.2f 单位（要 ≥ 3）" % [sp.player_id, d])
			return false
	return true


## 道具：到点刷新、走过去捡到、效果真的改属性
func _t_drops() -> bool:
	var la := _make_authority()
	# 快进到首刷（30s = 600 tick）
	_tick(la, LocalAuthority.KNOB_DROP_FIRST_TICKS + 2)
	if la.drops.is_empty():
		print("  首刷没出道具（tick=%d）" % la.tick)
		return false
	var d: Dictionary = la.drops[0]
	# 强制成瘦身，验「有效面积」被缩小但地盘计分不变
	d.kind = LocalAuthority.DROP_SLIM
	var area_before := la._area_permyriad(1)
	var eff_before := la._effective_area(1)
	la.players[1].pos_x = Fixed.world_to_fixed(d.pos.x)
	la.players[1].pos_y = Fixed.world_to_fixed(d.pos.y)
	_tick(la, 1)
	if not la.drops.is_empty():
		print("  站到坑位上没捡起来")
		return false
	if la.players[1].slim_ms <= 0:
		print("  瘦身效果没生效")
		return false
	if la._effective_area(1) >= eff_before:
		print("  有效面积没变小：%d → %d" % [eff_before, la._effective_area(1)])
		return false
	if la._area_permyriad(1) != area_before:
		print("  地盘计分被道具改了（不该改）：%d → %d" % [area_before, la._area_permyriad(1)])
		return false
	return true


## 0x0C2 ScoreTick 编解码来回一致（面积条的唯一数据源）。
## 之前 decode 先读 4×u16 再读 u32，与编码端相反 —— 面积条显示的是 tick 数值。
## verify_proto.py 没覆盖 0x0C2，所以这个 bug 一直没被抓到。
func _t_score_tick() -> bool:
	var w := ByteWriter.new(12)
	w.write_u32(12345)
	for v in [1111, 2222, 3333, 4444]:
		w.write_u16(v)
	var d := codec.decode_score_tick(w.data())
	if d.get("server_tick", 0) != 12345:
		print("  server_tick=%s 期望 12345" % d.get("server_tick", "无"))
		return false
	var expect := [1111, 2222, 3333, 4444]
	for i in range(4):
		if d.ratios[i] != expect[i]:
			print("  ratios=%s 期望 %s" % [d.ratios, expect])
			return false
	return true


## 战斗博弈：小形态 3 刀死；射程外挥击 = 长后摇（挥空惩罚）
func _t_combat_gameplay() -> bool:
	var la := _make_authority()
	la.vaults.clear()
	la.pallets.clear()
	# 数值对账：初始 10% → HP 100，小打小 3 刀
	var hp0 := Sim.hp_max_for_area(1000)
	if hp0 != 100:
		print("  10%% 的 HP = %d，期望 100" % hp0)
		return false
	var dmg := int(round(la.KNOB_ATTACK_DAMAGE * Sim.attack_mult_for_area(1000)))
	var hits := int(ceil(float(hp0) / float(dmg)))
	if hits != 3:
		print("  小打小需要 %d 刀（伤害 %d / 血 %d），期望 3 刀" % [hits, dmg, hp0])
		return false
	# 大的更耐打
	if Sim.hp_max_for_area(3500) <= hp0:
		print("  35%% 的 HP 没有更高")
		return false
	# 挥空惩罚：把目标放到射程外，挥一次，后摇必须是长的那个
	var me := _pos(la, 1)
	var reach := Sim.attack_range_for_area(1000)
	la.players[2].pos_x = Fixed.world_to_fixed(me.x + reach + 2.0)
	la.players[2].pos_y = Fixed.world_to_fixed(me.y)
	la.players[1].buttons = MsgIds.BUTTON_ACTION
	_tick(la, 1)
	la.players[1].buttons = 0
	_tick(la, 6)          # 前摇 200ms = 4 tick，走完就结算
	if la.players[1].atk_cd_ms < la.KNOB_ATTACK_WHIFF_MS - 400:
		print("  挥空没吃长后摇：cd=%d，期望接近 %d" % [la.players[1].atk_cd_ms, la.KNOB_ATTACK_WHIFF_MS])
		return false
	return true


## 死亡 → 地盘整片化回原汤（G0001：谁都能抢）
func _t_dissolve() -> bool:
	var la := _make_authority()
	var before := la._area_permyriad(2)
	if before <= 0:
		print("  Bot2 开局就没有地盘")
		return false
	la._dissolve_territory(2)
	if la._area_permyriad(2) != 0:
		print("  溶解后还剩 %d" % la._area_permyriad(2))
		return false
	return true


## 脱战 3s 且在扩张 → 回血
func _t_regen() -> bool:
	var la := _make_authority()
	la.players[1].hp = 40
	la.players[1].buttons = MsgIds.BUTTON_CHARGE
	_tick(la, 10)         # 脱战计时未到（开局 combat_ms=0，其实立刻就能回）
	if la.players[1].hp <= 40:
		print("  扩张中没有回血：%d" % la.players[1].hp)
		return false
	# 战斗中不回血
	la.players[1].hp = 40
	la.players[1]["combat_ms"] = 3000
	_tick(la, 10)
	if la.players[1].hp != 40:
		print("  战斗状态下仍在回血：%d" % la.players[1].hp)
		return false
	return true


## 移速：大小差距要够有感但不能是硬克制；出手期间必须走不快
func _t_move_tradeoff() -> bool:
	var small := Sim.speed_for_area(1000)
	var big := Sim.speed_for_area(3500)
	var ratio := float(big) / float(small)
	if ratio < 0.65 or ratio > 0.85:
		print("  大/小 移速比 = %.2f，期望落在 0.65~0.85（差一倍是硬克制，差太少没手感）" % ratio)
		return false
	var la := _make_authority()
	for pid in [2, 3, 4]:
		la.players.erase(pid)
	la.vaults.clear()
	la.pallets.clear()
	# 前摇期间的位移必须显著小于自由移动
	la.players[1].move_x = 100
	la.players[1].buttons = 0
	var p0 := _pos(la, 1)
	_tick(la, 4)
	var free_dist := _pos(la, 1).distance_to(p0)
	la.players[1].atk_windup_ms = 1000       # 强制处于前摇
	var p1 := _pos(la, 1)
	_tick(la, 4)
	var windup_dist := _pos(la, 1).distance_to(p1)
	if windup_dist >= free_dist * 0.6:
		print("  前摇期间还能跑：%.3f vs 自由 %.3f" % [windup_dist, free_dist])
		return false
	return true


## Snapshot 带攻击冷却，且每玩家 14B
func _t_snapshot_cd() -> bool:
	var w := ByteWriter.new(64)
	w.write_u32(7)
	w.write_u16(1)
	w.write_u8(1)
	w.write_u8(1); w.write_u16(100); w.write_u16(200)
	w.write_i8(0); w.write_i8(0); w.write_u16(0); w.write_u16(1000)
	w.write_u8(0); w.write_u8(88); w.write_u8(45)      # atkCd = 45×10 = 450ms
	var body := w.data()
	if body.size() != 7 + 14:
		print("  Snapshot 单玩家 %dB，期望 %dB" % [body.size(), 7 + 14])
		return false
	var d := codec.decode_snapshot(body)
	if d.size() == 0 or d.players.size() != 1:
		print("  解不出来")
		return false
	if d.players[0].get("atk_cd_ms", -1) != 450:
		print("  atk_cd_ms = %s，期望 450" % d.players[0].get("atk_cd_ms", "无"))
		return false
	if d.players[0].hp != 88:
		print("  hp 错位：%d" % d.players[0].hp)
		return false
	return true
