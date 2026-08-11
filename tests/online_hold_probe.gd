## online_hold_probe.gd — 联机「多人真的跑通了」验收探针（无头，进局后驻留）
## 与 online_probe.gd 的区别：收到第一帧快照不退出，而是驻留 HOLD_S 秒，
## 期间朝锅心推摇杆并充能扩张，最后校验四件事（缺一即 FAIL）：
##   1. 快照里 players == 4（不是「只有自己」的假通）
##   2. 快照 tick 持续推进
##   3. 地盘 auth tick 持续推进（0x0C1/0x0C3 真的在落地）
##   4. 至少 2 个远端玩家位置发生变化（各客户端的输入真的互相看得见）
## 用法：godot --headless --path . -s res://tests/online_hold_probe.gd P1
## 配合 server/tools/e2e_multi.sh 一键跑 4 客户端。

extends SceneTree

const HOLD_S := 15.0               # 进局后驻留秒数
const JOIN_TIMEOUT_MS := 60000     # 4 客户端错峰启动，进局等待要给够
const CENTER_FIXED := 24 * 64      # 世界中心 (24,24)，Fixed.POS_SCALE = 64
const MOVE_EPS := 8                # 位置变化阈值（fixed，8/64 = 0.125 世界单位）
const KEEP_RADIUS := 8 * 64        # 距锅心 8 世界单位内停步（别走进邻居的汤）

var _app: Node = null
var _battle: Node = null
var _nick := "P"
var _deadline_ms := 0
var _step := 0
var _hold_until_ms := 0

var _first_snap_tick := -1
var _last_snap_tick := 0
var _first_auth_tick := -1
var _last_auth_tick := 0
var _max_players := 0
var _first_pos := {}               # player_id → Vector2i(pos_x, pos_y) 首次观测
var _moved := {}                   # player_id → true（位置变化超阈值）
var _dir := Vector2.ZERO


var _shot_path := ""               # 非空 = 驻留中途截图（带窗口跑时用）
var _shot_done := false
var _shot_owner := -1              # 截图里角色脚下的汤色归属（0 = 一方都不是）


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_nick = args[0]
	if args.size() > 1:
		_shot_path = args[1]
	_deadline_ms = Time.get_ticks_msec() + JOIN_TIMEOUT_MS


func _process(delta: float) -> bool:
	if _step < 3 and Time.get_ticks_msec() > _deadline_ms:
		_fail("超时未进局: ui_state=%d" % (_app.ui_state if _app != null else -1))
		return true
	match _step:
		0:
			var main: Node = load("res://src/app/main.tscn").instantiate()
			root.add_child(main)
			_app = main
			_step = 1
		1:
			if _app.audio_mgr == null:
				return false
			_app.nickname = _nick
			_app.on_quick_match()
			print("[%s] 已发起快速匹配" % _nick)
			_step = 2
		2:
			if _app.ui_state == _app.UIState.IN_MATCH and _app.battle_root != null:
				_battle = _app.battle_root
				print("[%s] 进局! my_player_id=%d" % [_nick, _app.my_player_id])
				_disable_desktop_input()
				_app.transport.message_received.connect(_count_msg)
				_hold_until_ms = Time.get_ticks_msec() + int(HOLD_S * 1000.0)
				_step = 3
		3:
			_observe()
			_drive_input()
			_trace()
			_maybe_screenshot()
			if Time.get_ticks_msec() > _hold_until_ms:
				_verdict()
				return true
	return false


var _next_trace_ms := 0
var _msg_counts := {}            # msg_id → 到达次数（传输层真值，绕过上层过滤）


func _count_msg(_ch: int, msg_id: int, body: PackedByteArray) -> void:
	var k := "0x%03X" % msg_id
	if not _msg_counts.has(k):
		_msg_counts[k] = [0, 0]
	_msg_counts[k][0] += 1
	_msg_counts[k][1] = body.size()

## 每 2s 打一行客户端侧真值：快照里各玩家位置 / 地盘 tick / 解码丢包数。
func _trace() -> void:
	if Time.get_ticks_msec() < _next_trace_ms:
		return
	_next_trace_ms = Time.get_ticks_msec() + 2000
	var ms = _battle.match_state
	var poses := []
	for pid in ms.players:
		poses.append("%d:(%d,%d)" % [pid, ms.players[pid].get("pos_x", -1),
				ms.players[pid].get("pos_y", -1)])
	# 四个出生格（格坐标 24/72）上的归属：应当分别是 1/2/3/4，否则地盘落位镜像了
	var corners := []
	for c in [[24, 24], [72, 24], [24, 72], [72, 72]]:
		corners.append("(%d,%d)=%d" % [c[0], c[1], _battle.grid.owner_at(c[0], c[1])])
	var t: Node = _app.transport
	print("[%s] 出生格归属 %s" % [_nick, " ".join(corners)])
	print("[%s] trace me=%d snap=%d auth=%d 摇杆=%s 充能=%s pos=[%s] codec_drop=%d in=%s out=%s mal=%s" % [
		_nick, _app.my_player_id, ms.last_snapshot_tick, _battle.grid.last_auth_tick,
		_dir, _battle._charging, " ".join(poses),
		codec.drop_count,
		t.get("_packets_in"), t.get("_packets_out"), t.get("_malformed")])


## 无头环境没有真键盘，DesktopInput 每帧会把摇杆刷成 0，覆盖探针的合成输入。
func _disable_desktop_input() -> void:
	var di: Node = _battle.find_child("DesktopInput", true, false)
	if di != null:
		di.battle = null


func _observe() -> void:
	var ms = _battle.match_state
	var grid = _battle.grid
	if ms.last_snapshot_tick > 0:
		if _first_snap_tick < 0:
			_first_snap_tick = ms.last_snapshot_tick
		_last_snap_tick = maxi(_last_snap_tick, ms.last_snapshot_tick)
	if grid.last_auth_tick > 0:
		if _first_auth_tick < 0:
			_first_auth_tick = grid.last_auth_tick
		_last_auth_tick = maxi(_last_auth_tick, grid.last_auth_tick)
	_max_players = maxi(_max_players, ms.players.size())
	for pid in ms.players:
		var p: Dictionary = ms.players[pid]
		var here := Vector2i(int(p.get("pos_x", 0)), int(p.get("pos_y", 0)))
		if not _first_pos.has(pid):
			_first_pos[pid] = here
		elif absi(here.x - _first_pos[pid].x) > MOVE_EPS \
				or absi(here.y - _first_pos[pid].y) > MOVE_EPS:
			_moved[pid] = true


## 朝锅心推摇杆（避免贴墙卡住），进入锅心 KEEP_RADIUS 内就停下 ——
## 否则固定方向会让 4 个客户端斜穿整锅、走进邻居的汤里（截图会误读成配色错乱）。
## 1.5s 后开始充能扩张。
func _drive_input() -> void:
	var me: Dictionary = _battle.match_state.my_state()
	if me.is_empty():
		return
	var v := Vector2(CENTER_FIXED - int(me.get("pos_x", 0)),
			CENTER_FIXED - int(me.get("pos_y", 0)))
	_dir = v.normalized() if v.length() > KEEP_RADIUS else Vector2.ZERO
	_battle.set_move_stick(_dir)
	if Time.get_ticks_msec() > _hold_until_ms - int((HOLD_S - 1.5) * 1000.0):
		_battle.set_charging(true)


## 与 src/world/territory_3d.gdshader 的 pal_p1..pal_p4 / pal_broth 同值
const PALETTE := [
	Color(0.720, 0.300, 0.200),    # P1 番茄红
	Color(0.440, 0.550, 0.250),    # P2 青菜绿
	Color(0.840, 0.630, 0.250),    # P3 玉米黄
	Color(0.500, 0.360, 0.530),    # P4 茄紫
]
const COLOR_TOL := 0.16            # 与调色板色的最大 RGB 距离


## 驻留过 3/4 时截一张（此时 4 人都在动、地盘已铺开），带窗口跑才有内容。
## 同时**采样像素**判定脚下汤色（不靠眼睛读截图）：镜头锁自己，
## 角色四周一圈应当是自己的汤色。
func _maybe_screenshot() -> void:
	if _shot_done or _shot_path.is_empty():
		return
	if Time.get_ticks_msec() < _hold_until_ms - int(HOLD_S * 250.0):
		return
	_shot_done = true
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("[%s] 截图失败：视口无纹理（--headless 下没有渲染）" % _nick)
		return
	img.save_png(_shot_path)
	# 角色四周环形采样（半径 70..130 px，跳过角色本体与 HUD 中轴）
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	var votes := [0, 0, 0, 0]
	var samples := 0
	for r in range(70, 131, 10):
		for deg in range(0, 360, 6):
			var a := deg_to_rad(float(deg))
			var x := cx + int(cos(a) * float(r))
			var y := cy + int(sin(a) * float(r))
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			samples += 1
			var c := img.get_pixel(x, y)
			for i in range(4):
				var p: Color = PALETTE[i]
				if sqrt(pow(c.r - p.r, 2) + pow(c.g - p.g, 2) + pow(c.b - p.b, 2)) < COLOR_TOL:
					votes[i] += 1
					break
	var best := 0
	for i in range(4):
		if votes[i] > votes[best]:
			best = i
	_shot_owner = best + 1 if votes[best] > 0 else 0
	print("[%s] 截图 → %s (%dx%d) 环形采样 %d 点 四方汤色票数=%s → 脚下=%d 我=%d" % [
		_nick, _shot_path, img.get_width(), img.get_height(), samples,
		votes, _shot_owner, _app.my_player_id])


func _verdict() -> void:
	var remote_moved := 0
	for pid in _moved:
		if pid != _app.my_player_id:
			remote_moved += 1
	var my_cells: int = _battle.grid.count_owner(_app.my_player_id)
	var snap_adv := _last_snap_tick - maxi(_first_snap_tick, 0)
	var auth_adv := _last_auth_tick - maxi(_first_auth_tick, 0)
	print("[%s] 传输层收到的消息（msg_id → [次数, 最后 body 字节]）: %s" % [_nick, _msg_counts])
	print("[%s] 观测: players=%d snap_tick=%d..%d(+%d) auth_tick=%d..%d(+%d) 远端移动=%d 我的格子=%d" % [
		_nick, _max_players, _first_snap_tick, _last_snap_tick, snap_adv,
		_first_auth_tick, _last_auth_tick, auth_adv, remote_moved, my_cells])

	var fails: Array[String] = []
	if _max_players != 4:
		fails.append("players=%d != 4" % _max_players)
	if snap_adv <= 0:
		fails.append("快照 tick 没推进 (+%d)" % snap_adv)
	if _last_auth_tick <= 0:
		fails.append("没收到地盘 (auth_tick=0)")
	elif auth_adv <= 0:
		fails.append("地盘 auth tick 没推进 (+%d)" % auth_adv)
	if remote_moved < 2:
		fails.append("只看到 %d 个远端玩家动了，要求 >=2" % remote_moved)
	if _shot_owner >= 0 and _shot_owner != _app.my_player_id:
		fails.append("画面里脚下汤色是 %d 号的，不是我（%d 号）" % [_shot_owner, _app.my_player_id])

	if fails.is_empty():
		print("==== [%s] PASS ====" % _nick)
		quit(0)
	else:
		print("[%s] FAIL: %s" % [_nick, "; ".join(fails)])
		quit(1)


func _fail(msg: String) -> void:
	print("[%s] FAIL: %s" % [_nick, msg])
	if _app != null and _app.transport != null:
		var t: Node = _app.transport
		print("[%s] transport state=%s in=%s out=%s bad=%s mal=%s ui=%d my_id=%d" % [
			_nick, t.get_state(), t.get("_packets_in"), t.get("_packets_out"),
			t.get("_bad_magic"), t.get("_malformed"), _app.ui_state, _app.my_player_id])
	quit(1)
