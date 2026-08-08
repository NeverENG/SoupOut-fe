## sfx.gd — 全部 SFX 接口（A0001M03 资产清单的客户端映射）
## 时机铁律（A0001M02F04 —— 正确性，不是打磨）：
##   [本地立即] 挥舞前摇 / 扩张 / 翻窗起手 / 推板起手
##   [等服务器] 命中 / 受击 / 死亡 / 复活 / 拾取 / 僵持
## 无素材 → 程序化占位（synth_tone/noise）；正式资产按 A0001M14F01 命名放入
## assets/audio/sfx/sfx_{编号}_{名}.wav 后自动替换（load_or_synth）。

class_name SfxBus
extends Node

var am: AudioManager = null
var _expand_loop: AudioStreamPlayer = null
var _expand_progress := 0.0

const SFX_DIR := "res://assets/audio/sfx/"


func setup(p_am: AudioManager) -> void:
	am = p_am


## 加载正式素材，失败则合成占位（不阻塞开发）
func _load_or_synth(file_name: String, synth: AudioStream) -> AudioStream:
	var path := SFX_DIR + file_name
	if ResourceLoader.exists(path):
		var s := load(path)
		if s is AudioStream:
			return s
	return synth


# ══ 扩张（🔴 全项目最重要的音频，A0001M01F01）══════════════════════════════

func play_expand_start() -> void:
	## [本地立即] 自己向原汤的扩张是预测的
	if _expand_loop == null:
		_expand_loop = am.play_loop("expand", _load_or_synth("sfx_05_expand_loop.wav",
			AudioManager.synth_tone(220.0, 0.5, 0.25, false)), AudioManager.Bus.SFX_SELF)
	am.set_param("expand_pitch", 1.0)
	am.set_param("expand_lowpass", 0.0)


func update_expand_progress(progress: float) -> void:
	## 音高 + 低通截止跟随扩张进度上行（一个素材 + 约 20 行代码）
	_expand_progress = clampf(progress, 0.0, 1.0)
	am.set_param("expand_pitch", 1.0 + _expand_progress * 0.6)
	am.set_param("expand_lowpass", _expand_progress)
	if _expand_loop != null:
		_expand_loop.pitch_scale = 1.0 + _expand_progress * 0.6


func play_expand_end() -> void:
	## [本地立即] 松手即停
	if _expand_loop != null:
		_expand_loop.stop()
		_expand_loop.queue_free()
		_expand_loop = null
	am.play("expand_end", _load_or_synth("sfx_07_expand_end.wav",
		AudioManager.synth_tone(180.0, 0.25, 0.3)), AudioManager.Bus.SFX_SELF)


func play_charge_blocked() -> void:
	## [等服务器] 争议边界不预测，顶住由服务器裁决
	am.play("charge_blocked", _load_or_synth("sfx_08_expand_blocked.wav",
		AudioManager.synth_tone(140.0, 0.2, 0.3)), AudioManager.Bus.SFX_SELF)


# ══ 战斗 ══════════════════════════════════════════════════════════════════

func play_swing_windup() -> void:
	## [本地立即] 按下即播，不等服务器（A0001M02F04 第一条）
	am.play("swing_windup", _load_or_synth("sfx_14_swing_windup.wav",
		AudioManager.synth_tone(500.0, 0.12, 0.2)), AudioManager.Bus.SFX_SELF)


func play_hit(heavy: bool) -> void:
	## [等服务器确认] 命中
	am.play("hit", _load_or_synth("sfx_15_hit.wav",
		AudioManager.synth_tone(320.0 if heavy else 420.0, 0.15, 0.5)), AudioManager.Bus.SFX_SELF)


func play_hurt() -> void:
	## [等服务器] 受击
	am.play("hurt", _load_or_synth("sfx_16_hurt.wav",
		AudioManager.synth_tone(240.0, 0.2, 0.45)), AudioManager.Bus.SFX_SELF)


func play_death() -> void:
	## [等服务器] 死亡（食材散架 + 化汤"泄气"）
	am.play("death", _load_or_synth("sfx_17_death.wav",
		AudioManager.synth_noise(0.6, 0.5)), AudioManager.Bus.SFX_OTHERS)


func play_respawn() -> void:
	am.play("respawn", _load_or_synth("sfx_18_respawn.wav",
		AudioManager.synth_tone(400.0, 0.3, 0.3)), AudioManager.Bus.SFX_SELF)


# ══ 地形 ══════════════════════════════════════════════════════════════════

func play_pallet_down() -> void:
	## [本地立即] 推板起手
	am.play("pallet_down", _load_or_synth("sfx_12_pallet_down.wav",
		AudioManager.synth_noise(0.25, 0.5)), AudioManager.Bus.SFX_OTHERS)


func play_pallet_break() -> void:
	am.play("pallet_break", _load_or_synth("sfx_12b_pallet_break.wav",
		AudioManager.synth_noise(0.3, 0.4)), AudioManager.Bus.SFX_OTHERS)


func play_vault_start() -> void:
	## [本地立即] 翻窗起手（交互有自然前摇，正好掩盖 RTT）
	am.play("vault_start", _load_or_synth("sfx_11_vault_start.wav",
		AudioManager.synth_tone(600.0, 0.1, 0.25)), AudioManager.Bus.SFX_SELF)


func play_vault_end() -> void:
	am.play("vault_end", _load_or_synth("sfx_11b_vault_end.wav",
		AudioManager.synth_tone(700.0, 0.1, 0.2)), AudioManager.Bus.SFX_SELF)


# ══ 道具 / 环境 ═══════════════════════════════════════════════════════════

func play_pickup() -> void:
	## [等服务器] 拾取
	am.play("pickup", _load_or_synth("sfx_20_pickup.wav",
		AudioManager.synth_tone(880.0, 0.12, 0.3)), AudioManager.Bus.SFX_SELF)


func play_drop_splash() -> void:
	am.play("drop_splash", _load_or_synth("sfx_19_drop_splash.wav",
		AudioManager.synth_noise(0.4, 0.4)), AudioManager.Bus.SFX_OTHERS)


func play_ambient_bubble() -> void:
	## 汤锅咕嘟底噪（🔴，A0001M03 第 3 项）
	am.play("ambient_bubble", _load_or_synth("sfx_03_broth_loop.wav",
		AudioManager.synth_noise(1.0, 0.08)), AudioManager.Bus.AMBIENCE)


# ══ UI ════════════════════════════════════════════════════════════════════

func play_ui_click() -> void:
	am.play("ui_click", _load_or_synth("sfx_22_ui_click.wav",
		AudioManager.synth_tone(1000.0, 0.06, 0.2)), AudioManager.Bus.UI)


func play_countdown() -> void:
	am.play("countdown", _load_or_synth("sfx_23_countdown.wav",
		AudioManager.synth_tone(660.0, 0.2, 0.3)), AudioManager.Bus.UI)


func play_win() -> void:
	am.play("win", _load_or_synth("sfx_26_win.wav",
		AudioManager.synth_tone(880.0, 0.5, 0.3)), AudioManager.Bus.UI)


func play_stir_warn() -> void:
	## [等服务器] 搅拌 T−3s 预警
	am.play("stir_warn", _load_or_synth("sfx_08b_stir_warn.wav",
		AudioManager.synth_tone(200.0, 0.4, 0.25)), AudioManager.Bus.SFX_OTHERS)
