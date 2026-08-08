## soup_transport.gd — ISoupTransport 抽象基类（T0005M03F05 接缝）
## 上层永远不知道自己连的是真网络还是环回（fake_transport 实现同一接口）。
## 通道纪律（T0005M04F01）：上层通过 send_msg(msg_id, body) 自动推导通道，禁止手填。

class_name ISoupTransport
extends Node

enum State {
	CONNECTING,   # 握手进行中
	OPEN,         # 可用
	GRACE,        # 宽限期（断线判定后）
	CLOSED,       # 已关闭
}

# 生命周期
func connect_to(_host: String, _port: int, _token: PackedByteArray) -> void:
	push_error("ISoupTransport.connect_to 抽象方法")

func disconnect_from() -> void:
	push_error("ISoupTransport.disconnect_from 抽象方法")

## 每帧由 app 驱动，内部收包/重传/心跳（T0005M12：poll 不用 await）
func poll(_delta: float) -> void:
	push_error("ISoupTransport.poll 抽象方法")

## 大厅/结算/宽限期显式心跳（1Hz；Grace 期由子类提速为 2~4Hz 探针）
func tick_heartbeat(_delta: float) -> void:
	pass

# 收发
## 底层发送（显式指定通道，供实现与测试使用）
func send(_ch: int, _msg_id: int, _body: PackedByteArray) -> void:
	push_error("ISoupTransport.send 抽象方法")

## 上层唯一入口：按 msg_id 自动推导通道（T0005M04F01，编译期表）
func send_msg(msg_id: int, body: PackedByteArray) -> void:
	send(MsgIds.channel_for(msg_id), msg_id, body)

signal message_received(ch: int, msg_id: int, body: PackedByteArray)
signal state_changed(state: int)

# 观测（喂给 M05 时钟与 A0001 网络指示）
func get_srtt_ms() -> int:
	return 0

func get_rttvar_ms() -> int:
	return 0

func get_loss_permille() -> int:
	return 0

func get_state() -> int:
	return State.CLOSED

## 应用层检测到 5s 无包时调用（T0005M03F03）
func enter_grace() -> void:
	push_error("ISoupTransport.enter_grace 抽象方法")
