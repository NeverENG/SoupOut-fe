# SoupOut · Godot 客户端架构规划

> 上位契约：`T0005SoupClientGodot`（客户端技术规格，本文是其落地）
> 冻结契约：`T0001SoupOut M02/M03`（业务协议）· `T0002SoupEngine M03`（UDP 线路协议）
> 视觉/音频：`A0001SoupOut` · 数值：`D0001SoupOutBalance`

---

## 1. 分层（单向依赖，不得反向）

```
表现层 ui/ world/       依赖 Node/Scene，可 get_node/await
   │   ↓（只调用接口）
核心层 core/             纯 GDScript，不 extends Node，无 get_node/await，
   │                    可无头单测（唯一例外：Time 之外的单例一律不碰）
   ↓
网络层 net/ proto/       纯 GDScript，不 extends Node（udp_transport 由 app 驱动 poll）
```

**核心层纪律**（`T0005M02F01`）：`match_state / prediction / territory_grid / clock / fixed / sim`
不许 `get_node`、不许 `await`、不许碰 `Time` 之外的引擎单例 —— 它必须能在无头单测里跑。

---

## 2. 目录（对齐 `T0005M02F02`，增补 audio/ 与 maps/ 实现）

```
res://
├─ src/
│  ├─ net/           网络层
│  │  ├─ soup_transport.gd   # ISoupTransport 抽象基类（接缝）
│  │  ├─ udp_transport.gd    # T0002M03 客户端实现（Ch0-3、可靠层、分片、心跳、Grace 探针）
│  │  ├─ reliability.gd      # seq/ack/ack_bits · RTO(Jacobson/Karels) · 重传队列
│  │  ├─ reassembly.gd       # Ch2 分片重组
│  │  └─ fake_transport.gd   # 环回 + 故障注入（延迟/抖动/丢包/乱序/重复/全丢）
│  ├─ proto/         协议层（T0001M02 编解码，全部小端、全边界检查）
│  │  ├─ msg_ids.gd          # 段位表 + 通道映射（0x0C3 走 Ch2 的例外写死）
│  │  ├─ byte_reader.gd      # 小端读取，越界返回 null 并计数，绝不抛错
│  │  ├─ byte_writer.gd      # 小端写入
│  │  └─ codec.gd            # 全部消息 encode/decode
│  ├─ core/          核心层（纯 GDScript）
│  │  ├─ fixed.gd            # 定点数辅助（除法显式舍入，与 Go 逐位一致）
│  │  ├─ sim.gd              # 移动/扩张模拟（与服务端同规则）
│  │  ├─ clock.gd            # estServerTick(EWMA) + lead 计算
│  │  ├─ territory_grid.gd   # 双网格 authGrid/predOwner/predTick + 增量应用 + 预测扩张
│  │  ├─ prediction.gd       # 环形缓冲 + 回滚重放 + visualError 平滑
│  │  └─ match_state.gd      # 权威态镜像（Snapshot/FullState 写入）
│  ├─ world/         表现层
│  │  ├─ territory.gdshader  # GPU shader 渲染（等值线/颗粒/描边/漫开）
│  │  ├─ territory_renderer.gd
│  │  ├─ character.gd        # 三档体型 + 动画状态机 + 占位美术接口
│  │  ├─ pallet.gd vault.gd wall.gd stir.gd
│  │  └─ battle_camera.gd    # 跟随 + 按质量档 zoom
│  ├─ maps/
│  │  └─ map_data.gd         # 4 重旋转对称：8 板 12 窗 13 墙 + 出生点
│  ├─ audio/
│  │  ├─ audio_manager.gd    # bus / voice pool / 优先级 / 参数插值
│  │  └─ sfx.gd              # 全部 SFX 接口占位（无素材时安全空转）
│  ├─ ui/
│  │  ├─ hud/                # area_bar minimap stick_move stick_aim
│  │  │                      # self_status edge_alert compass top_bar hud
│  │  └─ flow/               # login main_menu char_select matchmaking
│  │                         # room settings result reconnect_overlay
│  └─ app/
│     ├─ app.gd              # 应用状态机 Boot/Connecting/Online/Lobby/InMatch/Grace/Ended
│     ├─ local_authority.gd  # 单机本地权威（P0 主交付：移动/扩张/边界对抗）
│     └─ tweak_panel.gd      # 实时调参面板（P0 必做项）
├─ assets/            # 按 A0001M14F01 命名；当前仅 .gitkeep，接口已留
└─ tests/             # 无头单测（test_runner.gd 统一入口）
```

---

## 3. 场景树（运行结构）

```
Main (Node)
├─ App (app.gd)                 # 状态机 + 服务定位（autoload 亦可，二选一；本方案用主场景挂载）
│  ├─ AudioManager (audio_manager.gd)   # 单例服务
│  └─ Sfx (sfx.gd)
├─ FlowRoot (Control)           # 全流程 UI 容器（login/main_menu/... 动态挂载）
├─ BattleRoot (Node2D)          # 对局容器（进入 InMatch 时实例化 battle.tscn）
│  ├─ World (Node2D)
│  │  ├─ TerrainLayer          # 墙/板/窗（A0001M06F03 层序 4）
│  │  ├─ CharacterLayer        # 4 名玩家（层序 5）
│  │  ├─ VfxLayer              # 层序 6
│  │  └─ TerritoryRenderer     # 层序 2（z 在角色之下、汤底之上）
│  ├─ BattleCamera (Camera2D)
│  └─ Hud (CanvasLayer)        # 层序 7，独立于世界坐标
└─ Tests (Node)                 # 仅 --headless 测试模式挂载
```

**渲染层序**（`A0001M06F03` 硬规则）：汤底 1 → 地盘场 2 → 地面 VFX 3 → 地形 4 → 角色 5 → 角色上 VFX 6 → HUD 7。

---

## 4. 关键接口

### 4.1 ISoupTransport 接缝（`T0005M03F05`，上层永远不知道连的是真网络还是环回）

```gdscript
class_name ISoupTransport
func connect_to(host: String, port: int, token: PackedByteArray) -> void
func disconnect_from() -> void
func poll(delta: float) -> void
func send(ch: int, msg_id: int, body: PackedByteArray) -> void
signal message_received(ch: int, msg_id: int, body: PackedByteArray)
signal state_changed(state: int)          # Connecting/Open/Grace/Closed
func get_srtt_ms() -> int
func get_rttvar_ms() -> int
func get_loss_permille() -> int
```

### 4.2 协议层 → 上层

```gdscript
# codec.gd 静态方法，失败返回 null（长度不符/未知 id → 丢弃并计数）
codec.encode_create_room(nickname) -> PackedByteArray
codec.decode_room_state(body) -> Dictionary   # 或 null
...
# msg_ids.gd 通道映射（编译期表，send 自动推导 ch，0x0C3 例外写死）
msg_ids.channel_for(msg_id) -> int
```

### 4.3 核心层 → 表现层（单向）

```gdscript
# territory_grid.gd（core）
grid.apply_delta(server_tick, body)         # 只写 authGrid
grid.apply_keyframe(server_tick, body)      # 整表覆盖 + 清预测
grid.start_prediction(player_id, input_tick) # 本地预测扩张（只吃原汤）
grid.get_last_auth_tick() -> int            # ← 唯一合法的 lastRecvTerritoryTick 来源

# prediction.gd（core）
pred.record_input(seq, move_x, move_y, aim, buttons)
pred.reconcile(ack_seq, auth_pos)           # 回滚 + 重放 + visualError
pred.get_render_pos() -> Vector2            # 含 visualError 平滑
```

### 4.4 表现事件 → 音效（`A0001M02F04` 时机铁律）

| 音效 | 触发 |
|---|---|
| 挥舞前摇 / 翻窗起手 / 推板起手 / 扩张 | **本地立即** |
| 命中 / 受击 / 死亡 / 复活 / 拾取 / 僵持 | **等服务器确认**（Snapshot 或事件） |

---

## 5. 状态机（`T0005M11`）

```
Boot → Disconnected → Connecting → Online → Lobby
Lobby → InMatch（0x040 + 0x0C3）→ Grace（5s 无包）→ InMatch / Disconnected
InMatch → Ended（0x041）→ Lobby
```

| 状态 | 输入循环 | 预测 | 心跳 |
|---|---|---|---|
| Lobby | ❌ | ❌ | 1 Hz 显式 |
| InMatch | ✅ 20 Hz | ✅ | PlayerInput 天然覆盖 |
| Grace | ❌ 停发输入 | ❌ 冻结 | **2~4 Hz 重连探针**（带原 conn_id） |

---

## 6. 数据流（单 tick）

```
输入(摇杆) → stick_move 采样 → app 组 0x080 PlayerInput（3 帧冗余 + 两个 baseline）
   → prediction.record_input → sim.step（本地立即移动）
   → territory_grid.start_prediction（按住时本地扩张，只吃原汤）
   ↓ transport.send（Ch1）
收 0x0C0 Snapshot → match_state.apply → prediction.reconcile（误差≤2/64 则不动）
收 0x0C1 TerritoryDelta → territory_grid.apply_delta → 校验 predOverlay 回退
渲染 → territory_renderer 上传 animValue → shader 绘制
```

---

## 7. 验收锚点（对照 V0001/T0005）

- P0 单机模式：`fake_transport + local_authority`，左摇杆双环、充能环、地盘 shader、挤压反馈（`T0005M15 C1`）
- 调参面板：实时拖 `expandRate / vaultSlope / heavyThreshold`（`V0001M02F01` 第 9 条）
- 双网格 AC：预测格在下一个地盘帧撤销（`T0005M07F03` 两条 Gherkin）
- ACK 纪律：`lastRecvTerritoryTick` 只由实际应用的 0x0C1/0x0C3/0x042 写入
- 无美术/无音频：全部走 `assets/` 路径与 `sfx.gd` 接口，缺失时程序化占位 + 安全空转
