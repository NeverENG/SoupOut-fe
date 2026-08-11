# SoupOut 客户端 · 开发命令
# Godot 未安装时可用 make check 做静态校验（tools/check_gd.py）

.PHONY: check test smoke flow all

# 静态校验（无 Godot 环境替代验证：括号/缩进/preload路径/类型引用）
check:
	python3 tools/check_gd.py
	python3 tools/verify_proto.py

# 无头单测（需 Godot 4.2+）—— 零件级
test:
	godot --headless --path . -s res://tests/test_runner.gd

# 玩法冒烟 —— 扩张/Bot/挥击/板子/翻窗/墙体，规则级
smoke:
	godot --headless --path . -s res://tests/solo_smoke.gd

# 全流程冒烟 —— main.tscn → 单机试玩 → 对局真的在 tick，"能不能玩"级
flow:
	godot --headless --path . -s res://tests/flow_smoke.gd

# 全部
all: check test smoke flow

# 启动游戏
run:
	godot --headless --import --path .
	godot --path .
