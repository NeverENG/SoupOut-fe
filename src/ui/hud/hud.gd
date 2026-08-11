## hud.gd — 战斗 HUD 组装（A0001M11，CanvasLayer 层序 7，独立于世界坐标）
## 面积条（M11F01）· 小地图（M11F02）· 左摇杆双环（M11F03）· 右摇杆（M11F04）
## 自身状态（M11F05）· 边缘告警（M11F06）· 化汤罗盘（M11F07）· 顶部信息（M11F08）
## 阵亡遮罩（3D 版新增，置于最顶层，由 match_state.is_dead 驱动）

extends Control

var battle: Node = null
var grid: TerritoryGrid = null
var match_state: MatchState = null
var me_id: int = 0

var top_bar: TopBar = null
var area_bar: AreaBar = null
var minimap: Minimap = null
var stick_move: StickMove = null
var stick_aim: StickAim = null
var self_status: SelfStatus = null
var edge_alert: EdgeAlert = null
var compass: Compass = null
var death_overlay: DeathOverlay = null


func setup(p_battle: Node, p_grid: TerritoryGrid, p_match_state: MatchState, p_me_id: int) -> void:
	battle = p_battle
	grid = p_grid
	match_state = p_match_state
	me_id = p_me_id
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	top_bar = TopBar.new()
	top_bar.setup(battle)
	add_child(top_bar)
	area_bar = AreaBar.new()
	area_bar.setup(me_id)
	add_child(area_bar)
	minimap = Minimap.new()
	minimap.setup(battle)
	add_child(minimap)
	# 触屏摇杆只在触屏设备上建。电脑端走 DesktopInput（键鼠），
	# 再画两个大圆纯属挡视野 —— 判定条件与 battle_root._build_desktop_input 一致。
	if DisplayServer.is_touchscreen_available():
		stick_move = StickMove.new()
		stick_move.setup(battle)
		add_child(stick_move)
		stick_aim = StickAim.new()
		stick_aim.setup(battle)
		add_child(stick_aim)
	self_status = SelfStatus.new()
	self_status.setup(battle)
	add_child(self_status)
	edge_alert = EdgeAlert.new()
	edge_alert.setup()
	add_child(edge_alert)
	compass = Compass.new()
	compass.setup()
	add_child(compass)
	# 阵亡遮罩（最后挂 = 最顶层；mouse IGNORE 不挡任何输入）
	death_overlay = DeathOverlay.new()
	add_child(death_overlay)
	death_overlay.hide()


## 0x0C2 ScoreTick 数据入口（面积条唯一数据源，T0005M07F06）
func on_score_tick(st: Dictionary) -> void:
	area_bar.on_score_tick(st.ratios)
	# 排名（按面积从大到小）
	var order: Array = match_state.player_ids()
	order.sort_custom(func(a, b): return st.ratios[a - 1] > st.ratios[b - 1])
	var rank := order.find(me_id) + 1
	top_bar.update_rank(rank, maxi(1, order.size()))


func _process(_delta: float) -> void:
	if match_state == null:
		return
	var me := match_state.my_state()
	if me.size() > 0:
		self_status.update_status(me.get("hp", 100), me.get("mass", 1000))
		# 充能时锁定右摇杆（A0001M11F04：扩张态禁用挥击）
		if stick_aim != null:      # 电脑端没有摇杆
			stick_aim.set_locked(match_state.is_charging(me_id))
	# 阵亡遮罩（权威 FLAG_DEAD 驱动，set_dead 内部去重）
	if death_overlay != null:
		death_overlay.set_dead(match_state.is_dead(me_id))
	# 炖煮计时（MatchStart 下发 stewTicks；占位 3:00）
	var total: int = 3600
	if battle != null:
		var _md = battle.get("_match_data")
		if _md is Dictionary:
			total = _md.get("stew_ticks", 3600)
	var elapsed := int(battle.soup_clock.est_server_tick) if battle != null else 0
	top_bar.update_timer(total - elapsed)
	# 搅拌倒计时（本地权威/服务端 StirWarn 驱动；占位取 battle.stir）
	if battle != null and battle.stir != null:
		top_bar.update_stir_countdown(int(maxf(0.0, battle.stir.next_stir_at)))
