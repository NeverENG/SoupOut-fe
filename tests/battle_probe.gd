## battle_probe.gd — 全链路对局冒烟:登录 → 单机 3 Bot → 跑 8 秒 → 截图退出
extends Node
var f := 0
func _ready() -> void:
	var app: Node = load("res://src/app/app.gd").new()
	app.name = "Main"
	add_child(app)
	await get_tree().process_frame
	app.on_login_done("大厨阿邦")
	await get_tree().process_frame
	app.on_solo_play(3)
	print("BATTLE STARTED")
func _process(_d: float) -> void:
	f += 1
	if f in [120, 300, 500]:
		get_viewport().get_texture().get_image().save_png("user://battle_%d.png" % f)
		print("SNAP battle_", f)
	if f == 520:
		get_tree().quit(0)
