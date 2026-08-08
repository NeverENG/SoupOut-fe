# SoupOut 客户端 · 实现落地文档

> 定位：设计文档（`T0005SoupClientGodot` / `T0001SoupOut` / `A0001SoupOut` / `D0001SoupOutBalance`）→ 代码落地的映射、
> 冻结契约的裁定与笔误标注、review 修复记录。新增需求先查本文件再动代码。

---

## 1. 设计 → 实现映射

| 设计文档 | 模块 | 落地位置 |
|---|---|---|
| `T0005M02F02` | 分层目录 | `src/net` `src/proto` `src/core` `src/world` `src/ui` `src/audio` `src/app` `src/maps` |
| `T0005M03F01` | UDP 线路协议（包头/四通道/MTU） | `src/net/udp_transport.gd` |
| `T0005M03F03` | 可靠层（RTO/回绕/重传） | `src/net/reliability.gd` |
| `T0005M03F04` | Ch2 分片重组 | `src/net/reassembly.gd` + `udp_transport._frag_and_send` |
| `T0005M03F05` | ISoupTransport 接缝 | `src/net/soup_transport.gd`（fake/udp 同接口） |
| `T0005M03F06` | Grace 期重连探针 | `udp_transport`（2~4Hz 纯 ACK）+ `app.gd` 断线判定 |
| `T0005M04` | T0001M02 编解码 | `src/proto/codec.gd` `byte_reader.gd` `byte_writer.gd` `msg_ids.gd` |
| `T0005M05` | tick 估计与 lead | `src/core/clock.gd` |
| `T0005M06` | 预测与和解 | `src/core/prediction.gd`（环形缓冲/回滚/visualError） |
| `T0005M07` | TerritoryField 双网格 | `src/core/territory_grid.gd`（authGrid/predOverlay/校验回退） |
| `T0005M07F05` | 地盘 GPU shader | `src/world/territory.gdshader` + `territory_renderer.gd` |
| `T0005M10` | 定点确定性 | `src/core/fixed.gd`（直邻 1024/斜邻 1448/expandRate 换算） |
| `T0005M11` | 应用状态机 | `src/app/app.gd` |
| `T0005M13` | 测试 | `tests/test_runner.gd`（无头单测） |
| `T0005M13F05` | 单机本地权威 | `src/app/local_authority.gd`（移动/扩张/边界对抗/累积式 Delta） |
| `A0001M02` | 音频薄层 | `src/audio/audio_manager.gd` `sfx.gd` |
| `A0001M07` | 五色/图案/边界渲染 | `territory.gdshader` 内建 palette + 图案函数 |
| `A0001M08` | 三档体型角色 | `src/world/character.gd` |
| `A0001M09` | 4 重对称地图（8 板 12 窗） | `src/maps/map_data.gd` |
| `A0001M10` | 跟随摄像机分级 zoom | `src/world/battle_camera.gd` |
| `A0001M11` | 战斗 HUD | `src/ui/hud/*.gd`（面积条/小地图/双环摇杆/告警/罗盘/顶部） |
| `A0001M13` | 全流程界面 | `src/ui/flow/*.gd`（登录/主菜单/选角/匹配/房间/设置/结算/重连） |
| `D0001M02/M03/M05` | 数值表与翻窗/扩张公式 | `src/core/sim.gd` `fixed.gd`（LUT + 公式，KNOB 走调参面板） |
| `V0001M02F01` 第 9 条 | 实时调参面板 | `src/app/tweak_panel.gd`（Tab 开关） |

---

## 2. 冻结契约的裁定与文档算术笔误（已按字段布局对齐）

> 原则：**字段布局是唯一真相**，文档中的"总字节数"是算术笔误时以字段求和为准，
> 已在代码注释与 `tools/verify_proto.py` 双重标注，服务端对端需对齐。

| 项 | 文档写 | 字段求和（实际） | 落地 |
|---|---|---|---|
| `0x080 PlayerInput` 总长 | 33 B / 3×6 | **30 B**（头部 7 + 3帧×5 + baseline 8；每帧 i8+i8+u16+u8=5B） | `codec.encode_player_input` / test 断言 30 |
| `0x0C0 Snapshot` 每玩家 | 14 B/player | **13 B**（u8+2×u16+2×i8+2×u16+2×u8） | `codec.decode_snapshot` 检查 13 |
| UDP 包头 | 14 B | **16 B**（magic u16+version u8+flags u8+conn_id u32+seq u16+ack u16+ack_bits u32） | `udp_transport.HEADER_LEN = 16` |
| `0x0C3 Keyframe` run | length u16+owner u8 | 3 B/run | 9 B 头部+run 样例 |
| `0x040 MatchStart` | — | 头部 13 B + 22 B/player | `codec.decode_match_start` 检查 13/22 |
| `0x042 FullState` | — | 头部 9 B + 16 B/player | `codec.decode_full_state` 检查 16 |
| `0x0C2 ScoreTick` | — | 12 B | 检查 12 |

**协议裁定（需服务端对齐）**

1. **序号空间全局统一**：所有包（含不可靠/心跳）共享一个 seq；可靠层重传队列按通道独立、ack 全局裁剪。
2. **ack 连续语义**：接收侧只确认"连续段"（`on_recv` 仅当 `dist==1` 推进 last_recv_seq），缺失帧不被确认 → 对端 RTO 重传补齐。
3. **Ch2 每 datagram 至多一条帧**：`T0002M03` 的"同 datagram 合并多条"仅适用于 Ch0/Ch1；Ch2 可靠帧独立 datagram（否则接收端墓碑去重会丢同 datagram 第二条 Ch2 帧）。
4. **Ch2 有序的工程权衡**：先到先投（无握手序号同步下不做严格 HOL blocking），有序性由 ①墓碑去重（每 seq 至多投递一次）②ack 连续语义（RTO 补齐缺失）③关键消息 serverTick 防回退（Keyframe/FullState 拒绝旧 tick）三层保证。
5. **P0 握手为明文直连占位**（`T0005M14F01`：T0002 握手包体格式未定），`connect_to` 发 flags.bit2 空包后直接置 OPEN。

---

## 3. 五轮 review 修复记录（已全部闭环）

| 轮次 | 发现 | 修复 |
|---|---|---|
| 1 | ByteWriter 前导 0（所有编码输出带 N 个 0） | 索引写入 + 长度跟踪，`data()` 返回精确切片 |
| 1 | 单机 fake 信号未连接（数据流断链） | `on_solo_play` 连接 message_received/state_changed |
| 1 | `_now_ms` 未声明（编译错误） | 重写 poll 后清除 |
| 1 | codec 8 处长度检查与字段求和不符 | 全部对齐（snapshot 13/match_start 13+22/full_state 16/score_tick 12/respawn 9/stir_sweep 4） |
| 1 | 分片帧 msg_id=0（重组后无法分发） | 分片帧携带真实 msg_id |
| 1 | reliability 无限指数退避 | RETRANS_ATTEMPT_MAX=16 → broken → 断连 |
| 2 | Ch2 expected 锚定首帧（乱序静默丢失） | 墓碑去重（seen）+ 先到先投 |
| 3 | 首帧立即投递破坏有序 + 去重失效（重复投递） | 工程裁定（见 §2-4）+ 墓碑保留 + serverTick 防回退 |
| 4 | Ch2 帧不参与 ack 记账（对端重传永不裁剪 → 超限断连） | `_ordered_deliver` 首行补 `_recv_tracker.on_recv(peer_seq)` |
| 4 | 同 datagram 多 Ch2 帧会被墓碑丢弃 | 协议裁定：Ch2 每 datagram 单帧（§2-3） |

最终轮 review 裁决：**pass（ship as-is）**。

---

## 4. 待上位文档提供（T0005M14）

| # | 项 | 客户端现状 |
|---|---|---|
| 1 | T0002 握手包体格式 | P0 明文直连占位（`udp_transport.connect_to` 标注替换点） |
| 2 | 逐包 HMAC 范围 | v2 加密再议（FLAG_ENCRYPT 占位） |
| 3 | `0x015 QuickMatchStatus` | 匹配页显示本地占位队列数 |
| 4 | `0x107 StirWarn` / `0x108 StirSweep` 布局 | 解码占位 + `stir.gd` 预告/扫过表现 |
| 5 | `0x0C4 BorderPressure` | `edge_alert.gd` / `compass.gd` 接口已留（set_pressure/罗盘数据源） |
| 6 | 三处字节笔误确认（§2） | 已按字段布局实现，需服务端对齐 |

---

## 5. 运行与验证

```bash
make check     # 静态校验 + 协议字节布局验证（无 Godot 环境可跑）
make test      # 无头单测（需 Godot 4.2+）：godot --headless -s res://tests/test_runner.gd
make run       # 启动游戏：godot --path .
```

- 单机原型：主菜单 → **单机试玩（P0）**，本地权威模拟服务端，验证"按住扩张/边界对抗/体型缩放"核心手感。
- 调参：对局中 **Tab** 打开实时调参面板（expandRate/moveSpeed）。
- 联网：连 Go 逻辑服经 soup-engine（`SettingsDb` 中 server_host/server_port，默认 127.0.0.1:12345）。
