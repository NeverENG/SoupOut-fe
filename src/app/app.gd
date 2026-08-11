## app.gd — SoupOut 客户端应用状态机与服务定位
## 对应 T0005M11（客户端应用状态机）+ M09F03（界面流程）
## 架构位：表现层顶部，唯一的编排者。持有 transport/audio/sfx 服务，切换 UI 流程与对局。
## 状态机（网络侧由 transport.state_changed 驱动）：
##   Boot → Disconnected → Connecting → Online(Lobby) → InMatch → Grace → InMatch/Disconnected
## 输入循环纪律（T0005M11 表）：Lobby 仅 1Hz 心跳；InMatch 20Hz；Grace 停发输入但 2~4Hz 探针。

extends Node

# ── 静态单例访问（主场景挂载，不依赖 autoload 配置）──────────────────────────
class_name App
static var instance: Node = null

# ── 应用状态（UI 层）────────────────────────────────────────────────────────
enum UIState {
	BOOT,          # 资源加载
	LOGIN,         # 本地昵称输入，零网络请求（A0001M13F01）
	MAIN_MENU,     # 主菜单（A0001M13F02）
	CHAR_SELECT,   # 角色选择（A0001M13F03）
	MATCHMAKING,   # 匹配中（A0001M13F04）
	ROOM,          # 房间（A0001M13F05）
	IN_MATCH,      # 对局中（A0001M11 HUD）
	RECONNECTING,  # 重连覆盖层（A0001M12F08）
	RESULT,        # 结算（A0001M13F07）
	DISCONNECTED,  # 已断开页
	SETTINGS,      # 设置（A0001M13F06）
}

# ── 引用（运行时挂载）────────────────────────────────────────────────────────
var transport: ISoupTransport = null          # 网络层（fake 或 udp，上层无感知）
var audio_mgr: AudioManager = null            # 音频薄层
var sfx: SfxBus = null                        # SFX 接口
var flow_root: Control = null                 # 全流程 UI 容器
var battle_root: Node = null                # 对局容器
var local_authority: LocalAuthority = null    # 单机本地权威（P0 主交付）

# ── 玩家本地偏好（A0001M13F03：主菜单选偏好，进房自动发一次）──────────────────
var nickname: String = "食材"
var ingredient_pref: int = 0                  # 0..3 → 排骨/紫菜/玉米/茄子
var my_player_id: int = 0
var my_room_code: String = ""
var bot_count_pref: int = 3                   # 人机练习：1~3 个 Bot（=2~4 人局），结算「再来一锅」复用

# ── 服务端下发的会话参数（T0005M14F01-4：不得硬编码，从服务端读）──────────────
var reconnect_grace_s: float = 20.0           # 默认 20s（T0001M01F02），等待下发覆盖

var ui_state: int = UIState.BOOT
var in_match: bool = false
var _last_room_state: Dictionary = {}      # 0x017 最新缓存（room_screen 读取）

# ── 信号（给测试与 UI 用）────────────────────────────────────────────────────
signal ui_state_changed(new_state: int)
signal match_started(match_start: Dictionary, keyframe_body: PackedByteArray)
signal match_ended(result: Dictionary)
signal kick_reason(reason: String)

const SCENE_MAIN_MENU := "res://src/ui/flow/main_menu.gd"
const SCENE_BATTLE := "res://src/app/battle.tscn"
const NET_TIMEOUT_NO_PACKET_S := 5.0          # 连续 5s 无包 → Grace（T0005M03F03）
const HANDSHAKE_TIMEOUT_S := 3.0              # 握手超时 3s（T0005M11）
const HUD_LAYER := 7                          # A0001M06F03 渲染层序

var _last_packet_time: float = 0.0
var _in_grace: bool = false
var _grace_elapsed: float = 0.0
var _match_data: Dictionary = {}              # 0x040 MatchStart 解码结果
var _pending_keyframe: PackedByteArray = PackedByteArray()


func _ready() -> void:
	instance = self
	# 全局主题(胡闹厨房式卡通 UI):挂在根窗口,所有 Control 自动继承
	get_window().theme = UiKit.build_theme()
	_register_services()
	_build_flow_root()
	set_ui_state(UIState.LOGIN)
	_enter_login()


func _register_services() -> void:
	audio_mgr = AudioManager.new()
	audio_mgr.name = "AudioManager"
	add_child(audio_mgr)
	audio_mgr.setup()
	sfx = SfxBus.new()
	sfx.name = "Sfx"
	add_child(sfx)
	sfx.setup(audio_mgr)


func _build_flow_root() -> void:
	flow_root = Control.new()
	flow_root.name = "FlowRoot"
	flow_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	flow_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(flow_root)


# ══ UI 状态切换 ════════════════════════════════════════════════════════════

func set_ui_state(new_state: int) -> void:
	if ui_state == new_state:
		return
	ui_state = new_state
	ui_state_changed.emit(new_state)


func _enter_login() -> void:
	var screen := preload("res://src/ui/flow/login_screen.gd").new()
	_show_flow(screen)


func _show_flow(screen: Control) -> void:
	for child in flow_root.get_children():
		child.queue_free()
	if screen != null:
		# 必须铺满 flow_root：否则 screen 的 size 是 (0,0)，
		# 它内部所有 PRESET_FULL_RECT / PRESET_CENTER / CenterContainer
		# 都相对这个零尺寸矩形解算，整页控件会全部堆到左上角。
		screen.set_anchors_preset(Control.PRESET_FULL_RECT)
		flow_root.add_child(screen)


# ══ 玩家动作（UI 调用入口）══════════════════════════════════════════════════

func on_login_done(nick: String) -> void:
	nickname = nick
	# 落盘：主菜单右上角与下次启动的默认值都读 SettingsDb，
	# 不写回的话这次输入的名字在菜单上根本不显示。
	SettingsDb.set_value("nickname", nick)
	set_ui_state(UIState.MAIN_MENU)
	_show_flow(preload("res://src/ui/flow/main_menu.gd").new())


func on_quick_match() -> void:
	_connect_and_send(func(): _send_lobby(MsgIds.QUICK_MATCH, codec.encode_quick_match(nickname)))
	set_ui_state(UIState.MATCHMAKING)
	_show_flow(preload("res://src/ui/flow/matchmaking.gd").new())


func on_create_room() -> void:
	_connect_and_send(func(): _send_lobby(MsgIds.CREATE_ROOM, codec.encode_create_room(nickname)))
	set_ui_state(UIState.MATCHMAKING)
	_show_flow(preload("res://src/ui/flow/matchmaking.gd").new())


func on_join_room(code4: String) -> void:
	_connect_and_send(func(): _send_lobby(MsgIds.JOIN_ROOM, codec.encode_join_room(code4, nickname)))
	set_ui_state(UIState.MATCHMAKING)
	_show_flow(preload("res://src/ui/flow/matchmaking.gd").new())


func on_practice_room() -> void:
	## 人机练习房（本地，不联网）：选 Bot 数量 → 开锅。
	## 联机路径协议未对齐，这条是目前唯一真能玩的入口，所以在主菜单是主按钮。
	_teardown_transport()
	_show_flow(preload("res://src/ui/flow/local_room_screen.gd").new())
	set_ui_state(UIState.ROOM)


func on_solo_play(bot_count: int = 3) -> void:
	## 单机原型模式（T0005M13F05：P0 主要交付物）：
	## fake_transport 环回 + 本地权威，上层无感知。
	bot_count = clampi(bot_count, 1, 3)
	bot_count_pref = bot_count
	_teardown_transport()
	var fake := FakeTransport.new()
	fake.set_fault(false, 0.0, 0.0, 0.0, 0.0, false, 0.0)   # 无故障注入
	transport = fake
	# 与 UdpTransport 路径同一条收包/状态管线（review 修复：缺了信号连接则单机断链）
	transport.message_received.connect(_on_message_received)
	transport.state_changed.connect(_on_transport_state)
	audio_mgr.configure_for_solo()
	local_authority = LocalAuthority.new()
	local_authority.name = "LocalAuthority"
	add_child(local_authority)
	local_authority.begin_match(nickname, ingredient_pref, bot_count)
	fake.attach_local_authority(local_authority)
	local_authority.attach_transport(fake)
	transport.connect_to("localhost", 0, PackedByteArray())   # 环回：置 OPEN
	_start_match_ui(local_authority.mock_match_start(), local_authority.mock_keyframe())


func on_select_ingredient(idx: int) -> void:
	ingredient_pref = idx
	if in_match or transport == null or ui_state == UIState.ROOM:
		_send_lobby(MsgIds.SELECT_INGREDIENT, codec.encode_select_ingredient(idx))


func on_set_ready(ready: bool) -> void:
	_send_lobby(MsgIds.SET_READY, codec.encode_set_ready(ready))


func on_leave_room() -> void:
	_send_lobby(MsgIds.LEAVE_ROOM, PackedByteArray())
	on_back_to_menu()


func on_back_to_menu() -> void:
	_teardown_transport()
	_end_battle()
	set_ui_state(UIState.MAIN_MENU)
	_show_flow(preload("res://src/ui/flow/main_menu.gd").new())


func on_show_settings() -> void:
	var screen := preload("res://src/ui/flow/settings_screen.gd").new()
	screen.from_ui_state = ui_state
	_show_flow(screen)
	set_ui_state(UIState.SETTINGS)


func on_show_char_select(return_to_practice: bool = false) -> void:
	var screen := preload("res://src/ui/flow/char_select.gd").new()
	screen.return_to_practice = return_to_practice
	_show_flow(screen)
	set_ui_state(UIState.CHAR_SELECT)


# ══ 网络连接 ═══════════════════════════════════════════════════════════════

var _pending_on_open: Callable = Callable()

func _connect_and_send(after_open: Callable) -> void:
	_pending_on_open = after_open
	if transport != null and transport.get_state() == ISoupTransport.State.OPEN:
		after_open.call()
		return
	_teardown_transport()
	transport = UdpTransport.new()
	transport.name = "Transport"
	add_child(transport)
	transport.message_received.connect(_on_message_received)
	transport.state_changed.connect(_on_transport_state)
	# 本地直连：token 零长度（T0005M01F03），P0 无鉴权
	transport.connect_to(SettingsDb.get_string("server_host", "127.0.0.1"),
		SettingsDb.get_int("server_port", 12345), PackedByteArray())


func _teardown_transport() -> void:
	if transport != null:
		transport.disconnect_from()
		transport.queue_free()
		transport = null
	if local_authority != null:
		local_authority.queue_free()
		local_authority = null
	_in_grace = false


func _on_transport_state(state: int) -> void:
	match state:
		ISoupTransport.State.OPEN:
			_last_packet_time = Time.get_ticks_msec() / 1000.0
			if not _pending_on_open.is_null():
				var cb := _pending_on_open
				_pending_on_open = Callable()
				cb.call()
			if ui_state == UIState.RECONNECTING:
				# 重连成功：等 0x042 FullState + 0x0C3 恢复（M09F04）
				pass
		ISoupTransport.State.GRACE:
			_in_grace = true
			_grace_elapsed = 0.0
			if ui_state == UIState.IN_MATCH:
				_show_reconnect_overlay()
		ISoupTransport.State.CLOSED:
			if _in_grace and ui_state in [UIState.IN_MATCH, UIState.RECONNECTING]:
				_on_disconnected()
			_in_grace = false


func _show_reconnect_overlay() -> void:
	var overlay := preload("res://src/ui/flow/reconnect_overlay.gd").new()
	overlay.grace_total_s = reconnect_grace_s
	_show_flow(overlay)
	set_ui_state(UIState.RECONNECTING)


func _on_disconnected() -> void:
	_end_battle()
	var screen := preload("res://src/ui/flow/disconnected_screen.gd").new()
	_show_flow(screen)
	set_ui_state(UIState.DISCONNECTED)


func _send_lobby(msg_id: int, body: PackedByteArray) -> void:
	if transport != null and transport.get_state() == ISoupTransport.State.OPEN:
		transport.send_msg(msg_id, body)


# ══ 收包分发（T0005M04F03：事件不改状态，铁律）══════════════════════════════

func _on_message_received(ch: int, msg_id: int, body: PackedByteArray) -> void:
	_last_packet_time = Time.get_ticks_msec() / 1000.0
	if _in_grace:
		# 收到任意服务端包 → 回 InMatch，等 FullState/Keyframe（T0005M03F06）
		_in_grace = false
	match msg_id:
		MsgIds.ROOM_CREATED:
			var d := codec.decode_room_created(body)
			if not d.is_empty():
				my_room_code = d.room_code
				my_player_id = d.your_player_id
				_show_room()
		MsgIds.JOIN_RESULT:
			var d := codec.decode_join_result(body)
			if not d.is_empty():
				if d.code == 0:
					my_player_id = d.your_player_id
					_show_room()
				else:
					_join_failed(d.code)
		MsgIds.ROOM_STATE:
			var d := codec.decode_room_state(body)
			if not d.is_empty():
				_last_room_state = d
				if in_match and battle_root != null and battle_root.has_method("on_server_message"):
					battle_root.call("on_server_message", msg_id, body)
		MsgIds.MATCH_START:
			var d := codec.decode_match_start(body)
			if not d.is_empty():
				_match_data = d
				_start_match_ui(d, _pending_keyframe)
		MsgIds.TERRITORY_KEYFRAME:
			_pending_keyframe = body
			if in_match and battle_root != null and battle_root.has_method("on_server_message"):
				battle_root.call("on_server_message", msg_id, body)
		MsgIds.MATCH_END:
			var d := codec.decode_match_end(body)
			if not d.is_empty():
				_end_battle()
				var screen := preload("res://src/ui/flow/result_screen.gd").new()
				screen.result = d
				_show_flow(screen)
				set_ui_state(UIState.RESULT)
		_:
			if in_match and battle_root != null and battle_root.has_method("on_server_message"):
				battle_root.call("on_server_message", msg_id, body)


func _join_failed(code: int) -> void:
	var reason := "房间不存在"
	if code == 2:
		reason = "房间已满"
	elif code == 3:
		reason = "房间已开局"
	_show_flow(preload("res://src/ui/flow/main_menu.gd").new())
	set_ui_state(UIState.MAIN_MENU)
	# 简单提示：复用断开页组件显示一行文案
	var tip := Label.new()
	tip.text = reason
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flow_root.add_child(tip)
	tip.set_anchors_preset(Control.PRESET_CENTER)
	tip.position = Vector2(-80, -40)
	kick_reason.emit(reason)


func _show_room() -> void:
	_show_flow(preload("res://src/ui/flow/room_screen.gd").new())
	set_ui_state(UIState.ROOM)


# ══ 对局生命周期 ═══════════════════════════════════════════════════════════

func _start_match_ui(match_start: Dictionary, keyframe: PackedByteArray) -> void:
	_end_battle()
	# 进局前清掉上一屏：原来只 _end_battle()，上一个 flow 屏会整块留在
	# 战斗世界底下 —— 看不见，但按钮还活着（房间的「开锅」、结算的「再来一锅」
	# 就压在战场上），点到直接重开一局。
	_show_flow(null)
	in_match = true
	set_ui_state(UIState.IN_MATCH)
	var scene := load(SCENE_BATTLE) as PackedScene
	if scene != null:
		battle_root = scene.instantiate()
		battle_root.name = "BattleRoot"
		add_child(battle_root)
		battle_root.call("begin_match", self, match_start, keyframe, transport)
	match_started.emit(match_start, keyframe)


func _end_battle() -> void:
	in_match = false
	if battle_root != null:
		battle_root.queue_free()
		battle_root = null


func _unhandled_input(event: InputEvent) -> void:
	if ui_state == UIState.IN_MATCH and in_match and battle_root != null:
		if battle_root.has_method("on_unhandled_input"):
			battle_root.call("on_unhandled_input", event)


# ══ 心跳与断线判定 ═════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if transport != null:
		transport.poll(delta)
		if ui_state in [UIState.MAIN_MENU, UIState.MATCHMAKING, UIState.ROOM, UIState.RESULT] \
				and transport.get_state() == ISoupTransport.State.OPEN:
			transport.tick_heartbeat(delta)   # 大厅/结算显式 1Hz 心跳（T0005M03F03）
		if ui_state in [UIState.IN_MATCH, UIState.RECONNECTING] and not _in_grace:
			var now := Time.get_ticks_msec() / 1000.0
			if now - _last_packet_time > NET_TIMEOUT_NO_PACKET_S and transport.get_state() == ISoupTransport.State.OPEN:
				transport.enter_grace()
	if _in_grace:
		_grace_elapsed += delta
		if _grace_elapsed >= reconnect_grace_s:
			_in_grace = false
			_on_disconnected()


func get_grace_elapsed() -> float:
	return _grace_elapsed
