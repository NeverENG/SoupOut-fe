# SoupOut 客户端（Godot 4.x）

> **一口汤锅，4 个食材各占一角。按住扩张把自己的汤铺出去，铺得越大人越壮。**
> 玩法：`docs/G0001SoupOut` · 客户端技术：`docs/T0005SoupClientGodot` · 协议（冻结）：`docs/T0001SoupOut M02`
> 数值：`docs/D0001SoupOutBalance` · 美术音频：`docs/A0001SoupOut` · 验收：`docs/V0001SoupOutP0`
> **实现落地：`docs/IMPLEMENTATION.md`**（设计→实现映射、协议裁定与笔误标注、review 修复记录）

## 这是什么

SoupOut 的 Godot 4.x 客户端，按 `T0005SoupClientGodot` 的分层架构实现：

| 层 | 目录 | 说明 |
|---|---|---|
| 表现层 | `src/ui/` `src/world/` | HUD/全流程界面 · 地盘 shader/角色/地形/摄像机 |
| 核心层 | `src/core/` | 纯 GDScript 不 extends Node：双网格、预测回滚、tick 时钟、定点模拟 |
| 网络层 | `src/net/` `src/proto/` | T0002M03 UDP 线路协议客户端半边 · T0001M02 全消息编解码 |
| 音频 | `src/audio/` | bus 树 / voice pool / 优先级 / 参数插值 + 全部 SFX 接口占位 |
| 应用 | `src/app/` | 状态机 · 单机本地权威（P0 主交付）· 调参面板 |

**单向依赖**：表现层 → 核心层 → 网络层。核心层无 `get_node` / `await` / 引擎单例，可无头单测。

## 运行

需要 **Godot 4.2+**（本机未安装，代码按 4.x API 编写，首次打开即导入）。

```bash
# 启动（主场景 src/app/main.tscn）
godot --path .

# 无头单测（T0005M13）
godot --headless -s res://tests/test_runner.gd

# 无 Godot 环境下的静态校验（本仓库自带）
#   check_gd.py：GDScript 括号/缩进/preload 路径/类型引用
#   verify_proto.py：T0001M02 协议字节布局独立复核（含文档算术笔误标注）
make check
```

## 怎么玩（P0 单机原型）

主菜单 → **单机试玩（P0）**，进入 4 人混战（你 + 3 Bot，本地权威模拟服务端）：

- **左摇杆外圈** 拖出 = 移动
- **左摇杆内圈** 长按 ≥0.12s = 充能扩张（按住看自己的汤一圈圈漫出去、角色变大）
- **右摇杆** 拖出朝向 / 抬手挥击
- **Tab** = 实时调参面板（拖 `expandRate` / `moveSpeed`，P0 必做项）

联网模式（连 Go 逻辑服经 soup-engine）：主菜单「开锅！」快速匹配 / 「和朋友炖」建房 / 「输入房间码」进房。
P0 握手为明文直连占位（`T0005M14F01`：T0002 握手包体格式未定，已在 `udp_transport.gd` 标注替换点）。

## 关键实现点（对文档的落位）

| 文档裁定 | 落位 |
|---|---|
| 双网格 authGrid/predOverlay（M07F03） | `src/core/territory_grid.gd`，含预测校验回退 + 只吃原汤 |
| ACK 纪律（M07F02，写错被踢） | `grid.last_auth_tick` 唯一写入者 = 0x0C1/0x0C3/0x042 |
| GPU shader 地盘渲染（M07F05） | `src/world/territory.gdshader`（等值线/颗粒带/描边/漫开 + 五色图案），`Linear` 过滤是有意例外 |
| 20Hz 输入循环 + 3 帧冗余 + 双 baseline（M02F04/M05F03） | `src/app/battle_root.gd` |
| 可靠层 RTO/回绕/重传 + Ch2 分片（M03F03/F04） | `src/net/reliability.gd` `reassembly.gd` |
| 单机本地权威（M13F05，P0 主交付） | `src/app/local_authority.gd`（移动/扩张/边界对抗/累积式 Delta） |
| 调参面板（V0001M02F01 第 9 条） | `src/app/tweak_panel.gd`（Tab 开关） |

## 美术与音频接入（无素材，接口已留）

- **美术**：所有占位（圆+大眼睛角色 / 色块地形 / 程序化 shader 图案）都有替换点注释。
  正式资产按 `A0001M14F01` 命名放入 `assets/`：
  - 角色：`assets/temp/chr/chr_{paigu|zicai|yumi|qiezi}_{anim}_{frame}.png`（动画表见 `A0001M08F03`）
  - 地形：`assets/temp/ter/ter_*.png` · UI：`assets/temp/ui/ui_*.png` · 特效：`assets/temp/fx/fx_*.png`
- **音频**：`src/audio/sfx.gd` 已含全部 SFX 接口（带 `[本地立即]`/`[等服务器]` 时机注释，`A0001M02F04`）。
  把素材放 `assets/audio/sfx/sfx_{编号}_{名}.wav` 即自动替换程序化占位（`audio_manager.gd` 的 `synth_*`）。
  扩张循环音（🔴 全项目最重要）接口：`play_expand_start / update_expand_progress / play_expand_end`。

## 测试

`tests/test_runner.gd` 覆盖：协议 roundtrip 与通道映射（含 0x0C3→Ch2 例外）· 协议 fuzz（任意字节不崩）·
双网格 AC（未认领预测格撤销 / ACK 不受预测影响）· 只吃原汤 · u16 序号回绕 · 分片重组 ·
Ch2 有序投递（乱序/重复帧）· 预测回滚重放 · expandRate 换算（10%→50% 120s 逐位校验，`D0001M05F01`）。

**协议裁定（与服务端对齐）**：`T0002M03` 的"同一 datagram 合并多条消息"仅适用于 Ch0/Ch1；
Ch2 可靠帧每 datagram 至多一条（客户端已如此实现，服务端需对齐，否则 Ch2 同 datagram 多帧会被墓碑去重丢弃）。

## 待上位文档提供（`T0005M14`）

1. `T0002` 握手包体格式（P0 明文直连绕开）· 2. 逐包 HMAC 范围（v2 加密再议）
3. `T0001` 新增 `0x015 QuickMatchStatus` / `0x107 StirWarn` / `0x108 StirSweep` / `0x0C4 BorderPressure`（UI 已留接口：匹配队列数、搅拌预警、边缘告警/推力条数据源）
