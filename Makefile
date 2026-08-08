# SoupOut 客户端 · 开发命令
# Godot 未安装时可用 make check 做静态校验（tools/check_gd.py）

.PHONY: check test

# 静态校验（无 Godot 环境替代验证：括号/缩进/preload路径/类型引用）
check:
	python3 tools/check_gd.py
	python3 tools/verify_proto.py

# 无头单测（需 Godot 4.2+）
test:
	godot --headless -s res://tests/test_runner.gd

# 启动游戏
run:
	godot --path .
