## byte_reader.gd — 小端读取器，全边界检查（T0005M03F01：解析器必须对任意字节序列安全）
## 越界返回 null / 缺省值并计数，绝不抛错、绝不崩（对齐 T0002M08F02）。
## 纯 GDScript，不 extends Node。

class_name ByteReader

var _data: PackedByteArray
var _pos: int = 0
var _overread: int = 0          # 越界计数（喂给诊断）

const NICKNAME_LEN := 16


func _init(data: PackedByteArray) -> void:
	_data = data
	_pos = 0


func remaining() -> int:
	return _data.size() - _pos


func eof() -> bool:
	return _pos >= _data.size()


func pos() -> int:
	return _pos


func overread_count() -> int:
	return _overread


func _need(n: int) -> bool:
	if _pos + n > _data.size():
		_overread += 1
		return false
	return true


func read_u8() -> int:
	if not _need(1):
		return 0
	var v := _data[_pos]
	_pos += 1
	return v


func read_i8() -> int:
	var v := read_u8()
	if v >= 128:
		v -= 256
	return v


func read_u16() -> int:
	if not _need(2):
		return 0
	var v := _data[_pos] | (_data[_pos + 1] << 8)
	_pos += 2
	return v


func read_u32() -> int:
	if not _need(4):
		return 0
	var v := _data[_pos] | (_data[_pos + 1] << 8) | (_data[_pos + 2] << 16) | (_data[_pos + 3] << 24)
	_pos += 4
	return v


## varint：T0001M03F06 差值编码（低 7 位 + 续位，小端字节序）
func read_varint() -> int:
	var result := 0
	var shift := 0
	while true:
		if not _need(1):
			return result
		var b := _data[_pos]
		_pos += 1
		result |= (b & 0x7F) << shift
		if (b & 0x80) == 0:
			break
		shift += 7
		if shift > 28:
			_overread += 1   # 防畸形 varint 无限增长
			break
	return result


## 定长 UTF-8 字符串：不足补 \0，超长按字节截断且不得切断多字节字符（T0005M04F02）
func read_fixed_string(n: int) -> String:
	if not _need(n):
		return ""
	var raw := _data.slice(_pos, _pos + n)
	_pos += n
	var end := raw.size()
	# 截到最后一个完整 UTF-8 序列的边界
	while end > 0 and (raw[end - 1] == 0 or (raw[end - 1] & 0xC0) == 0x80):
		if raw[end - 1] == 0:
			end -= 1
			break
		end -= 1
	var s := raw.slice(0, end).get_string_from_utf8()
	# get_string_from_utf8 遇非法字节会替换为 U+FFFD，可接受（不抛错）
	return s


func read_bytes(n: int) -> PackedByteArray:
	if not _need(n):
		return PackedByteArray()
	var v := _data.slice(_pos, _pos + n)
	_pos += n
	return v


func read_rest() -> PackedByteArray:
	var v := _data.slice(_pos)
	_pos = _data.size()
	return v
