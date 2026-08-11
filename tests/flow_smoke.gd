## flow_smoke.gd — 全流程冒烟（无头）
## 跑法：godot --headless --path . -s res://tests/flow_smoke.gd
##
## 验的是「点得进去、跑得起来」：
## 加载 main.tscn → App 起来 → 触发单机试玩 → 4 名角色在场 → 键鼠输入挂上 → 权威真的在 tick。
## 这条过了才谈得上「游戏能玩」，单测全绿只代表零件是好的。
##
## 用引擎真实主循环驱动（_process），不手工 pump ——
## _initialize 阶段 SceneTree 还没建好，那时候 add_child 是挂不上的。

extends SceneTree

## 权威 20Hz。默认 expandRate=64 时 R 每 tick 只涨 8，而最近一圈格的测地距离是 1024，
## 也就是第一格要 128 tick（6.4s）才翻 —— 跑 4 秒会误判成「扩张没生效」。
const TARGET_TICKS := 300         # 15 秒，足够翻过两圈

var _step := 0
var _frames := 0
var _app: Node = null
var _battle: Node = null
var _area_before := -1
var _y_before := 0
var _mark := 0
var _max_r := 0
var _ok := true


## 注入真实按键事件。Input.parse_input_event 在 --headless 下也会更新
## Input.is_key_pressed 读的那份状态，所以能真正驱动 DesktopInput 的轮询。
func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames > 20000:
		_fail("超时：主循环跑了 20000 帧还没走完流程")
		return true
	match _step:
		0:
			var main: Node = load("res://src/app/main.tscn").instantiate()
			root.add_child(main)
			_app = main
			_step = 1
		1:
			if not _app.is_inside_tree():
				return false
			if not _app.has_method("on_solo_play"):
				_fail("App 脚本没起来（main.tscn 根节点上没有 app.gd）")
				return true
			if _app.audio_mgr == null:
				return false          # 等 _ready 跑完
			_pass("main.tscn 加载 + App 就位（_ready 已跑）")
			_app.nickname = "smoke"
			_app.on_solo_play()
			_step = 2
		2:
			_battle = _find_battle()
			if _battle == null:
				return false
			_pass("单机对局建立（BattleRoot + LocalAuthority）")
			if _battle.characters.size() != 4:
				_fail("角色数 = %d，期望 4" % _battle.characters.size())
			else:
				_pass("4 名角色在场")
			if _battle.get_node_or_null("DesktopInput") == null:
				_fail("DesktopInput 没挂上（电脑端没法操作）")
			else:
				_pass("键鼠调试输入已挂载")
			# 触屏能力判定：真为 true 的话 _build_desktop_input 会直接 return，
			# 正式窗口模式下键盘路径就整条不存在了 —— 必须确认它是 false。
			if DisplayServer.is_touchscreen_available():
				_fail("DisplayServer.is_touchscreen_available() = true，键鼠输入不会挂载")
			else:
				_pass("非触屏设备判定正确（键鼠路径会生效）")
			# ── 真的按 W：注入按键，看权威里的坐标动没动 ──
			_y_before = _app.local_authority.players[1].pos_y
			_key(KEY_W, true)
			_mark = _app.local_authority.tick
			_step = 3
		3:
			var la3: Node = _app.local_authority
			if la3.tick < _mark + 20:
				return false
			var y_now: int = la3.players[1].pos_y
			if y_now >= _y_before:
				_fail("按住 W 人没往上走：pos_y %d → %d" % [_y_before, y_now])
			else:
				_pass("W 键生效：pos_y %d → %d（向上 %.2f 世界单位）"
					% [_y_before, y_now, (_y_before - y_now) / 64.0])
			_key(KEY_W, false)
			# ── 真的按空格：看充能位有没有进到权威的 buttons ──
			_key(KEY_SPACE, true)
			_mark = la3.tick
			_step = 4
		4:
			var la4: Node = _app.local_authority
			if la4.tick < _mark + 10:
				return false
			if la4.players[1].buttons & MsgIds.BUTTON_CHARGE == 0:
				_fail("按住空格没有进入充能态（buttons=%d）" % la4.players[1].buttons)
			else:
				_pass("空格键生效：权威侧已进入充能态")
			_area_before = la4._area_permyriad(1)
			_mark = la4.tick
			_step = 5
		5:
			var la: Node = _app.local_authority
			# 过程中采样：玩家在 4 人局里可能被打死，
			# 而死亡溶解会把 _expand_r 清掉 —— 只看终值会误判成「扩张没生效」。
			_max_r = maxi(_max_r, la.grid._expand_r.get(1, 0))
			if la.tick < _mark + TARGET_TICKS:
				return false
			var a1: int = la._area_permyriad(1)
			# 断言「扩张机制在运作」，不是「净面积必涨」——
			# 这是 4 人真实对局，站着按 16 秒会被 Bot 打、地盘会被抢，
			# 净面积完全可能是负的（实测 8.51% → 6.13%）。
			var r := _max_r
			if la.tick <= 0:
				_fail("权威没有 tick")
			elif r <= 0:
				_fail("按住扩张：扩张半径没有增长（_expand_r=%d）" % r)
			else:
				_pass("对局在跑：tick=%d，扩张半径峰值 R=%d，面积 %.2f%% → %.2f%%（对局中会被打死/被抢，净值可正可负）"
					% [la.tick, r, _area_before / 100.0, a1 / 100.0])
			print("==== 全流程冒烟：%s ====" % ("通过" if _ok else "不通过"))
			quit(0 if _ok else 1)
			return true
	return false


func _find_battle() -> Node:
	for c in _app.get_children():
		if c.has_method("_run_input_tick"):
			return c
	return null


func _pass(msg: String) -> void:
	print("[PASS] ", msg)


func _fail(msg: String) -> void:
	_ok = false
	print("[FAIL] ", msg)
