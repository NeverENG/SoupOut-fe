## msg_ids.gd — T0001M02F01 段位表 + 通道映射（编译期表，禁止手填）
## 通道推导规则（T0005M04F01）：
##   0x010–0x03F 大厅 → Ch2  0x040–0x07F 对局控制 → Ch2
##   0x080–0x0BF 输入 → Ch1  0x0C0–0x0FF 同步 → Ch0，但 0x0C3 走 Ch2（例外写死）
##   0x100–0x13F 事件 → Ch3
## 纯 GDScript，不 extends Node（网络层契约，可无头单测）。

class_name MsgIds

# ── 通道常量 ────────────────────────────────────────────────────────────────
const CH_UNRELIABLE_UNORDERED := 0   # Ch0 同步（S→C）
const CH_UNRELIABLE_SEQUENCED := 1   # Ch1 输入（C→S）
const CH_RELIABLE_ORDERED := 2       # Ch2 大厅/对局控制/Keyframe
const CH_RELIABLE_UNORDERED := 3     # Ch3 事件（S→C）

# ── 大厅（Ch2，T0001M02F02）────────────────────────────────────────────────
const CREATE_ROOM := 0x010           # C→S nickname[16]
const ROOM_CREATED := 0x011          # S→C roomCode[4] · yourPlayerId u8
const JOIN_ROOM := 0x012             # C→S roomCode[4] · nickname[16]
const JOIN_RESULT := 0x013           # S→C code u8 · yourPlayerId u8
const QUICK_MATCH := 0x014           # C→S nickname[16]
# 0x015 空号（T0005M14F02-1：建议 QuickMatchStatus，待 T0001 补充）
const LEAVE_ROOM := 0x016            # C→S —
const ROOM_STATE := 0x017            # S→C 广播
const SELECT_INGREDIENT := 0x018     # C→S ingredientId u8
const SET_READY := 0x019             # C→S ready u8
const ROOM_CLOSED := 0x01A           # S→C reason u8

# ── 对局控制（Ch2，T0001M02F03）────────────────────────────────────────────
const MATCH_START := 0x040           # S→C
const MATCH_END := 0x041             # S→C
const FULL_STATE := 0x042            # S→C 重连/纠偏

# ── 输入（Ch1，T0001M02F04）─────────────────────────────────────────────────
const PLAYER_INPUT := 0x080          # C→S 20Hz，携带最近 3 帧冗余

# ── 同步（Ch0，T0001M02F05）─────────────────────────────────────────────────
const SNAPSHOT := 0x0C0              # S→C 20Hz
const TERRITORY_DELTA := 0x0C1       # S→C 10Hz
const SCORE_TICK := 0x0C2            # S→C 1Hz
const TERRITORY_KEYFRAME := 0x0C3    # S→C 每 5s/开局/重连 —— ⚠️ 走 Ch2（例外）

# ── 事件（Ch3，T0001M02F06）─────────────────────────────────────────────────
const PLAYER_DIED := 0x100           # victim u8 · killer u8 · tick u32
const PLAYER_RESPAWN := 0x101        # playerId u8 · posX u16 · posY u16 · tick u32
const PALLET_DOWN := 0x102           # palletId u8 · byPlayer u8 · tick u32
const DROP_SPAWN := 0x103            # dropId u8 · type u8 · posX u16 · posY u16
const DROP_TAKEN := 0x104            # dropId u8 · playerId u8
const VAULT_START := 0x105           # playerId u8 · vaultId u8 · durationTicks u8
const VAULT_END := 0x106             # playerId u8
# 0x107 StirWarn / 0x108 StirSweep —— 待 T0001 补充（T0005M14F02-2/3），预留常量
const STIR_WARN := 0x107
const STIR_SWEEP := 0x108

# ── 按钮位（T0001M02F04：buttons u8）───────────────────────────────────────
const BUTTON_ATTACK := 1             # bit0 —— 现在的语义是「万能动作」，见下
const BUTTON_CHARGE := 2             # bit1 充能扩张（按住语义！）
const BUTTON_INTERACT := 4           # bit2 交互（旧三键方案遗留，客户端不再发；权威仍兼容）
const BUTTON_SKILL := 8              # bit3 技能（预留）

## 万能动作位。操作已收敛成「摇杆 + 万能键」两个控件：
##   短按 → BUTTON_ACTION，权威按「近窗翻窗 > 近板推板 > 否则挥击」分发
##   长按 → BUTTON_CHARGE
## 线上仍复用 bit0，协议字节布局不变（T0001M02F04 无需改版）。
const BUTTON_ACTION := BUTTON_ATTACK

# ── stateFlags 位（T0001M02F05 Snapshot）────────────────────────────────────
const FLAG_CHARGING := 1             # bit0 充能中
const FLAG_VAULTING := 2             # bit1 翻窗中
const FLAG_DEAD := 4                 # bit2 死亡
const FLAG_INVULN := 8               # bit3 复活无敌
const FLAG_WINDUP := 16              # bit4 攻击前摇
const FLAG_OVERWEIGHT := 32          # bit5 过重（禁板子）


## 通道映射（编译期表）。0x0C3 例外写死 —— 全项目最容易写错的一处。
static func channel_for(msg_id: int) -> int:
	if msg_id == TERRITORY_KEYFRAME:
		return CH_RELIABLE_ORDERED
	elif msg_id >= 0x100:
		return CH_RELIABLE_UNORDERED
	elif msg_id >= 0x0C0:
		return CH_UNRELIABLE_UNORDERED
	elif msg_id >= 0x080:
		return CH_UNRELIABLE_SEQUENCED
	elif msg_id >= 0x040:
		return CH_RELIABLE_ORDERED
	elif msg_id >= 0x010:
		return CH_RELIABLE_ORDERED
	return CH_RELIABLE_ORDERED  # 0x000–0x00F 框架保留段，兜底走可靠


## 该消息是否客户端发出（C→S）
static func is_client_to_server(msg_id: int) -> bool:
	return msg_id in [CREATE_ROOM, JOIN_ROOM, QUICK_MATCH, LEAVE_ROOM,
		SELECT_INGREDIENT, SET_READY, PLAYER_INPUT]


## 该消息是否走 Ch2（可靠有序）—— 用于可靠层分片判定
static func is_reliable(msg_id: int) -> bool:
	var ch := channel_for(msg_id)
	return ch == CH_RELIABLE_ORDERED or ch == CH_RELIABLE_UNORDERED
