## settings_db.gd — 本地设置持久化（user://settings.cfg）
## A0001M13F06 设置项的存取；也存服务器地址（T0001M01F01：零后端，仅本地直连配置）。

class_name SettingsDb

const PATH := "user://settings.cfg"

static var _cfg: ConfigFile = null


static func _ensure() -> void:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)


static func get_string(key: String, default: String) -> String:
	_ensure()
	return _cfg.get_value("app", key, default)


static func get_int(key: String, default: int) -> int:
	_ensure()
	return _cfg.get_value("app", key, default)


static func get_float(key: String, default: float) -> float:
	_ensure()
	return _cfg.get_value("app", key, default)


static func get_bool(key: String, default: bool) -> bool:
	_ensure()
	return _cfg.get_value("app", key, default)


static func set_value(key: String, value) -> void:
	_ensure()
	_cfg.set_value("app", key, value)
	_cfg.save(PATH)


## 默认值（A0001M13F06 / D0001 / A0001M15F01）
static func defaults() -> Dictionary:
	return {
		"server_host": "127.0.0.1",
		"server_port": 12345,
		"nickname": "食材",
		"ingredient_pref": 0,
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 1.0,
		"shake_intensity": 1.0,       # 震屏强度（含 0 = 关闭档，A0001M13F06）
		"hitstop_intensity": 1.0,     # 顿帧强度
		"particle_density": 1.0,
		"colorblind_mode": false,     # 色盲模式（提高图案对比度，A0001M07F02）
		"hold_threshold": 0.12,       # KNOB_hold_threshold（A0001M15F01-5）
		"floating_stick": false,      # 浮动摇杆
		"left_stick_sens": 1.0,
		"right_stick_sens": 1.0,
	}
