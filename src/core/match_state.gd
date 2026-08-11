## match_state.gd — 权威态镜像（T0005M04F03：0x0C0/0x042 的写入者）
## 所有玩家状态以 Snapshot 为准；事件（0x100+）不得改这里（铁律）。
## 纯 GDScript，不 extends Node。

class_name MatchState
extends RefCounted

## player_id → {pos_x, pos_y, vel_x, vel_y, aim, mass, state_flags, hp, death_count, respawn_at_tick}
var players := {}
var last_snapshot_tick: int = 0
var ack_input_seq: int = -1
var stew_remain_ticks: int = 0
var match_duration_ticks: int = 0
var my_id: int = 0


func set_me(player_id: int) -> void:
	my_id = player_id


func apply_snapshot(snap: Dictionary) -> void:
	last_snapshot_tick = snap.server_tick
	ack_input_seq = snap.ack_input_seq
	for p in snap.players:
		players[p.player_id] = {
			"pos_x": p.pos_x, "pos_y": p.pos_y,
			"vel_x": p.vel_x, "vel_y": p.vel_y,
			"aim": p.aim, "mass": p.mass,
			"state_flags": p.state_flags, "hp": p.hp,
		}


func apply_full_state(fs: Dictionary) -> void:
	last_snapshot_tick = fs.server_tick
	stew_remain_ticks = fs.stew_remain
	players.clear()
	for p in fs.players:
		players[p.player_id] = {
			"pos_x": p.pos_x, "pos_y": p.pos_y,
			"vel_x": 0, "vel_y": 0,
			"aim": p.aim, "mass": p.mass,
			"state_flags": p.state_flags, "hp": p.hp,
			"death_count": p.death_count, "respawn_at_tick": p.respawn_at_tick,
		}


func get_player(player_id: int) -> Dictionary:
	return players.get(player_id, {})


func is_me(player_id: int) -> bool:
	return player_id == my_id


func my_state() -> Dictionary:
	return get_player(my_id)


func is_dead(player_id: int) -> bool:
	var p := get_player(player_id)
	return p.get("state_flags", 0) & MsgIds.FLAG_DEAD != 0


func is_charging(player_id: int) -> bool:
	var p := get_player(player_id)
	return p.get("state_flags", 0) & MsgIds.FLAG_CHARGING != 0


## 本局实际在场的玩家 id（升序）。
## HUD 排名的分母以前写死 4，2/3 人局会显示「2/4」。
func player_ids() -> Array:
	var ids: Array = players.keys()
	ids.sort()
	return ids


func is_vaulting(player_id: int) -> bool:
	var p := get_player(player_id)
	return p.get("state_flags", 0) & MsgIds.FLAG_VAULTING != 0


func is_overweight(player_id: int) -> bool:
	var p := get_player(player_id)
	return p.get("state_flags", 0) & MsgIds.FLAG_OVERWEIGHT != 0


func my_area_permyriad() -> int:
	## mass 由面积派生、服务器算好下发（T0001M02F05：客户端不重算）
	return area_permyriad_of(my_id)


## 任意玩家的面积万分比（头顶信息条与领先者标记要用）
func area_permyriad_of(player_id: int) -> int:
	return int(get_player(player_id).get("mass", 0))
