## byte_writer.gd — 小端写入器（T0001M01F03：全部小端）
## 热路径纪律（T0005M12）：复用预分配实例，避免每帧 new。
## 容量预分配 + 索引写入 + 长度跟踪：data() 只返回实际写入的字节（无前导 0）。
## 纯 GDScript，不 extends Node。

class_name ByteWriter

var _data: PackedByteArray = PackedByteArray()
var _len: int = 0


func _init(capacity: int = 64) -> void:
	_data = PackedByteArray()
	_data.resize(maxi(capacity, 8))


## 已写入的字节数
func size() -> int:
	return _len


## 实际写入的字节（精确切片，无前导 0）
func data() -> PackedByteArray:
	return _data.slice(0, _len)


func _put(v: int) -> void:
	if _len >= _data.size():
		_data.resize(_data.size() * 2)
	_data[_len] = v & 0xFF
	_len += 1


func write_u8(v: int) -> void:
	_put(v)


func write_i8(v: int) -> void:
	_put(v)


func write_u16(v: int) -> void:
	_put(v)
	_put(v >> 8)


func write_u32(v: int) -> void:
	_put(v)
	_put(v >> 8)
	_put(v >> 16)
	_put(v >> 24)


## varint：与 reader 对称的低 7 位 + 续位
func write_varint(v: int) -> void:
	var x := v & 0xFFFFFFFF
	while true:
		var b := x & 0x7F
		x >>= 7
		if x != 0:
			_put(b | 0x80)
		else:
			_put(b)
			break


## 定长 UTF-8：按字节截断且不得切断多字节字符，不足补 \0（T0005M04F02）
func write_fixed_string(s: String, n: int) -> void:
	var raw := s.to_utf8_buffer()
	if raw.size() > n:
		# 从第 n 字节往回找 UTF-8 序列边界（不切断多字节字符）
		var cut := n
		while cut > 0 and (raw[cut - 1] & 0xC0) == 0x80:
			cut -= 1
		raw = raw.slice(0, cut)
	for i in range(raw.size()):
		_put(raw[i])
	for i in range(n - raw.size()):
		_put(0)


func write_bytes(b: PackedByteArray) -> void:
	for i in range(b.size()):
		_put(b[i])
