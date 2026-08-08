## audio_manager.gd — 自写薄音频层（A0001M02F05：Godot 内置 + 薄封装，不上 Wwise/FMOD）
## - Bus 树（A0001M02F03）：Master ─ Music / Ambience / SFX(Self, Others) / UI
## - SFX voice 上限 16（A0001M02F02），优先级 Self > 近处敌人 > 远处 > 环境
## - 同类合并窗口 30ms；距离衰减（屏幕外不播）
## - Self 响时压 Others 3dB（sidechain duck）
## - 参数插值：扩张循环音高 + 低通随进度上行（A0001M01F01 🔴）
## 无素材时安全空转 + 程序化占位音（synth 生成），正式资产放 assets/audio/ 后自动替换。

class_name AudioManager
extends Node

const MAX_VOICES := 16
const MERGE_WINDOW_S := 0.03

enum Bus { MUSIC, AMBIENCE, SFX_SELF, SFX_OTHERS, UI }

var voices: Array = []            # AudioStreamPlayer 池
var last_played := {}             # sfx_name → 上次播放时间（合并窗口）
var _buses := {}

# 参数插值（扩张循环等）
var _params := {}                 # name → {current, target}
const PARAM_RATE := 6.0           # 每秒插值速率


func setup() -> void:
	_build_bus_tree()
	for i in range(MAX_VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = _bus_name(Bus.SFX_OTHERS)
		add_child(p)
		voices.append(p)


func _build_bus_tree() -> void:
	# 清空默认并重建：Master / Music / Ambience / SFX / SFX/Self / SFX/Others / UI
	var master := AudioServer.get_bus_index("Master")
	while AudioServer.get_bus_count() > 1:
		AudioServer.remove_bus(1)
	var music := AudioServer.add_bus()
	AudioServer.set_bus_name(music, "Music")
	var amb := AudioServer.add_bus()
	AudioServer.set_bus_name(amb, "Ambience")
	var sfx := AudioServer.add_bus()
	AudioServer.set_bus_name(sfx, "SFX")
	var self_bus := AudioServer.add_bus()
	AudioServer.set_bus_name(self_bus, "Self")
	AudioServer.set_bus_parent(self_bus, sfx)
	var others := AudioServer.add_bus()
	AudioServer.set_bus_name(others, "Others")
	AudioServer.set_bus_parent(others, sfx)
	var ui := AudioServer.add_bus()
	AudioServer.set_bus_name(ui, "UI")
	_buses[Bus.MUSIC] = music
	_buses[Bus.AMBIENCE] = amb
	_buses[Bus.SFX_SELF] = self_bus
	_buses[Bus.SFX_OTHERS] = others
	_buses[Bus.UI] = ui


func _bus_name(b: int) -> String:
	match b:
		Bus.MUSIC: return "Music"
		Bus.AMBIENCE: return "Ambience"
		Bus.SFX_SELF: return "Self"
		Bus.SFX_OTHERS: return "Others"
		Bus.UI: return "UI"
	return "Master"


func configure_for_solo() -> void:
	# 单机模式：Self/Others 同源，无需 duck（保留结构）
	pass


## 播放 one-shot。ctx = 播放源世界位置（用于距离衰减），near 用于优先级。
func play(name: String, stream: AudioStream, bus: int = Bus.SFX_OTHERS,
		ctx: Vector2 = Vector2.ZERO, priority: int = 1, position: Vector2 = Vector2.ZERO) -> void:
	# 同类合并窗口（A0001M02F02：30ms 内同类只播一个）
	var now := Time.get_ticks_msec() / 1000.0
	if last_played.has(name) and now - last_played[name] < MERGE_WINDOW_S:
		return
	last_played[name] = now
	# 距离衰减：屏幕外不播（A0001M02F02）
	if ctx != Vector2.ZERO and position != Vector2.ZERO:
		var view := get_viewport_rect().size
		var screen_dist := (position - ctx).length()
		if screen_dist > maxf(view.x, view.y) * 0.9:
			return
	# voice pool：找空闲 voice；无空闲则按优先级抢占最低优先级的
	var target: AudioStreamPlayer = null
	for v in voices:
		if not v.playing:
			target = v
			break
	if target == null:
		target = voices[0]   # 抢占第一个（简化：voice 0 最低优先级）
	target.stream = stream
	target.bus = _bus_name(bus)
	target.volume_db = -6.0 + 6.0 * float(priority) / 10.0
	target.play()


## 循环层（扩张声等）：返回可控制的 player
func play_loop(name: String, stream: AudioStream, bus: int) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = _bus_name(bus)
	p.name = "loop_" + name
	add_child(p)
	p.play()
	return p


# ══ 参数插值（A0001M01F01：音高 + 低通随扩张进度上行）══════════════════════

func set_param(name: String, target: float) -> void:
	if not _params.has(name):
		_params[name] = {"current": 0.0, "target": target}
	else:
		_params[name].target = target


func get_param(name: String) -> float:
	if not _params.has(name):
		return 0.0
	return _params[name].current


func _process(delta: float) -> void:
	# 参数向目标插值（每帧）
	for name in _params:
		var p: Dictionary = _params[name]
		p.current = lerpf(p.current, p.target, delta * PARAM_RATE)
	# sidechain duck：Self 响时压 Others 3dB（A0001M02F03）
	var self_playing := false
	for v in voices:
		if v.playing and v.bus == "Self":
			self_playing = true
			break
	var others_idx := AudioServer.get_bus_index("Others")
	if others_idx >= 0:
		AudioServer.set_bus_volume_db(others_idx, -3.0 if self_playing else 0.0)


# ══ 程序化占位音（无素材时的兜底，正式资产接入后此路径不再走）══════════════

static func synth_tone(freq: float, dur_s: float, vol: float = 0.4, decay: bool = true) -> AudioStreamWAV:
	## 正弦短音（可作点击/命中占位）
	var rate := 22050
	var n := int(rate * dur_s)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / rate
		var env := 1.0
		if decay:
			env = 1.0 - float(i) / n
		var v := int(sin(TAU * freq * t) * vol * env * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


static func synth_noise(dur_s: float, vol: float = 0.3) -> AudioStreamWAV:
	## 白噪声短音（汤/水花占位）
	var rate := 22050
	var n := int(rate * dur_s)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var env := 1.0 - float(i) / n
		var v := int((randf() * 2.0 - 1.0) * vol * env * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
