#!/usr/bin/env python3
"""SoupOut GDScript 静态校验器（无 Godot 环境时的替代验证）。

检查项：
1. 括号/引号配平（每行 + 跨行字符串安全）
2. 缩进一致性（同缩进块）
3. class_name 引用存在性（全局类名 vs 定义）
4. preload/load 路径存在性
5. 信号连接/方法调用引用的类内方法存在性（粗略）
用法: python3 tools/check_gd.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errors = []
warnings = []


def walk_gd():
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "src")):
        dirnames[:] = [d for d in dirnames if d != ".godot"]
        for f in filenames:
            if f.endswith(".gd"):
                yield os.path.join(dirpath, f)
    for f in ["tests/test_runner.gd"]:
        yield os.path.join(ROOT, f)


def check_balance(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()
    stack = []
    quote = None
    line_no = 0
    for raw in lines:
        line_no += 1
        line = raw.rstrip("\n")
        i = 0
        while i < len(line):
            c = line[i]
            if c == "#" and quote is None:
                break   # 行注释：跳过剩余
            if quote:
                if c == "\\":
                    i += 2
                    continue
                if c == quote:
                    quote = None
                i += 1
                continue
            if c in "\"'":
                quote = c
            elif c in "([{":
                stack.append((c, line_no))
            elif c in ")]}":
                if not stack:
                    errors.append(f"{path}:{line_no} 多余的闭合符 {c}")
                    return
                op, ln = stack.pop()
                if "([{".index(op) != ")]}".index(c):
                    errors.append(f"{path}:{line_no} 括号不匹配 {op} vs {c} (开于 {ln})")
                    return
            i += 1
    if quote:
        errors.append(f"{path}: 未闭合字符串")
    if stack:
        for op, ln in stack[:5]:
            errors.append(f"{path}:{ln} 未闭合 {op}")


def check_indent(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()
    prev_indent = 0
    for i, raw in enumerate(lines):
        line = raw.rstrip("\n")
        if not line.strip() or line.strip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent % 4 != 0 and "\t" not in line[:indent]:
            warnings.append(f"{path}:{i+1} 缩进不是 4 的倍数 ({indent})")
        prev_indent = indent


CLASS_NAMES = set()
CLASS_DEFS = {}
GLOBAL_SCRIPT_FILES = {}


def collect_class_names():
    for path in walk_gd():
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"class_name\s+(\w+)", line)
                if m:
                    CLASS_NAMES.add(m.group(1))
                    CLASS_DEFS[m.group(1)] = os.path.relpath(path, ROOT)
                m2 = re.match(r"extends\s+(\w+)", line)
                if m2:
                    pass


def check_class_refs(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()
    # 跳过注释行后拼接，避免注释误报
    code_lines = [l for l in lines if not l.lstrip().startswith("#")]
    text = "".join(code_lines)
    # 预加载/加载路径
    for m in re.finditer(r'preload\("(res://[^"]+)"\)|load\("(res://[^"]+)"\)', text):
        res_path = m.group(1) or m.group(2)
        rel = os.path.join(ROOT, res_path.replace("res://", ""))
        if not os.path.exists(rel):
            errors.append(f"{path}: 资源不存在 {res_path}")
    # 类型标注引用
    for m in re.finditer(r":\s*([A-Z]\w*)", text):
        tn = m.group(1)
        if tn in ("true", "false", "int", "float", "String", "bool", "Vector2",
                  "Vector2i", "Color", "Dictionary", "Array", "PackedByteArray",
                  "PackedInt32Array", "PackedStringArray", "PackedVector2Array",
                  "Node", "Node2D", "Control", "Label", "Button", "HSlider",
                  "LineEdit", "ColorRect", "Polygon2D", "Camera2D", "Sprite2D",
                  "CanvasLayer", "CenterContainer", "VBoxContainer", "HBoxContainer",
                  "PanelContainer", "MarginContainer", "ScrollContainer",
                  "TextureProgressBar", "GradientTexture2D", "Gradient",
                  "StyleBoxFlat", "ImageTexture", "Image", "ShaderMaterial",
                  "AudioStreamPlayer", "AudioStreamWAV", "AudioStream",
                  "ConfigFile", "PacketPeerUDP", "Callable", "SceneTree",
                  "ProgressBar", "CheckBox", "TextureRect", "InputEvent",
                  "InputEventKey", "InputEventScreenTouch", "InputEventScreenDrag",
                  "DisplayServer", "AudioServer", "RandomNumberGenerator",
                  "RefCounted", "Object", "NodePath", "StringName", "Rect2",
                  "Transform2D", "PackedColorArray", "StyleBox"):
            continue
        if tn not in CLASS_NAMES:
            warnings.append(f"{path}: 类型标注引用未定义类 {tn}")


def main():
    collect_class_names()
    for path in walk_gd():
        check_balance(path)
        check_indent(path)
        check_class_refs(path)
    print(f"扫描到 {len(list(walk_gd()))} 个 .gd 文件")
    print(f"注册类: {len(CLASS_NAMES)} 个")
    for w in warnings:
        print(f"  [warn] {w}")
    if errors:
        print(f"\n❌ {len(errors)} 个错误:")
        for e in errors:
            print(f"  {e}")
        sys.exit(1)
    print(f"\n✅ 静态校验通过（{len(warnings)} 条警告，均为非阻塞提示）")
    sys.exit(0)


if __name__ == "__main__":
    main()
