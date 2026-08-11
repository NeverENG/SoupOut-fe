## online_probe.gd — 联机端到端探针（无头）
## 用真实 App 流程走 快速匹配 → 房间 → 对局 → 收快照。
## 用法（需先起 Go 逻辑服 + BanNet serve）：
##   godot --headless --path . -s res://tests/online_probe.gd P1
## 与 server/tools/e2e_local.sh 配合可一键 4 客户端验证。

extends SceneTree

var _frames := 0
var _app: Node = null
var _battle: Node = null
var _nick := "P"
var _deadline_ms := 0
var _step := 0
var _ok := false
var _mark := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_nick = args[0]
	_deadline_ms = Time.get_ticks_msec() + 30000


func _process(_delta: float) -> bool:
	_frames += 1
	if Time.get_ticks_msec() > _deadline_ms:
		_fail("超时: ui_state=%d" % (_app.ui_state if _app != null else -1))
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
			var st: int = _app.ui_state
			if st == _app.UIState.IN_MATCH and _app.battle_root != null:
				_battle = _app.battle_root
				print("[%s] 进局! my_player_id=%d ui=%d" % [_nick, _app.my_player_id, st])
				_step = 3
				_mark = Time.get_ticks_msec()
		3:
			if _battle.match_state != null and _battle.match_state.last_snapshot_tick > 0:
				var ms: Dictionary = _battle.match_state.my_state()
				print("[%s] 收到快照 tick=%d pos=(%s) players=%s" % [
					_nick, _battle.match_state.last_snapshot_tick, ms.get("pos_x", -1),
					_battle.match_state.players.size()])
				_ok = true
				print("==== [%s] PASS ====" % _nick)
				quit(0)
				return true
			if Time.get_ticks_msec() - _mark > 10000:
				_fail("进局后 10s 没收到快照")
				return true
	return false


func _fail(msg: String) -> void:
	print("[%s] FAIL: %s" % [_nick, msg])
	if _app != null and _app.transport != null:
		var t: Node = _app.transport
		print("[%s] transport state=%s packets_in=%s out=%s bad=%s mal=%s last_recv=%s ui=%d my_id=%d match_data=%s" % [
			_nick, t.get_state(), t.get("_packets_in"), t.get("_packets_out"),
			t.get("_bad_magic"), t.get("_malformed"),
			t.get("_recv_tracker").get("last_recv_seq"), _app.ui_state,
			_app.my_player_id, _app.get("_match_data").size() if _app.get("_match_data") != null else -1])
	quit(1)
