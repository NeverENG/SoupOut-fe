#!/usr/bin/env python3
"""verify_proto.py — 协议字节布局验证（不依赖 Godot，独立复核 codec/ByteWriter 语义）
对应 T0001M02 冻结契约。文档中的算术笔误在此标注：
  - PlayerInput 总长 30B（文档写 33B；字段 i8+i8+u16+u8 = 5B/帧）
  - Snapshot 每玩家 14B（13B 原字段 + attackCdMs10 u8，正好回到文档的 14B/player）
  - UDP 包头 16B（文档写 14B；magic+version+flags+conn_id+seq+ack+ack_bits 求和 16B）
⚠️ 这个脚本只验证「客户端自己前后一致」，**不代表能和服务端对上**。
   PlayerInput 目前是客户端 30B 平铺（lastRecvSnapshotTick 用 u32），
   而服务端按 BanNet SDK 契约收：8B 头（clientTick u32 · inputSeq u16 ·
   lastRecvSnapshotTick **u16**）+ 20B body，整包 28B。
   两边差 2 字节且字段错位，真连上服务端会把第一帧的 moveX 当成 frameCount。
   下面那句 assert len(d) == 30 是照旧文档写的，它通过 ≠ 协议是对的。
   决定以哪边为准之后，这里和 src/proto/codec.gd 要一起改。
   （单机模式走 local_authority，碰不到这条，所以不阻塞 P0。）

用法: python3 tools/verify_proto.py
"""
import sys


class W:
    """模拟 ByteWriter 修复后语义：容量预分配 + 索引写入 + 长度跟踪（data 无前导 0）"""

    def __init__(self, cap=64):
        self.d = bytearray(max(cap, 8))
        self.n = 0

    def _put(self, v):
        if self.n >= len(self.d):
            self.d *= 2
        self.d[self.n] = v & 0xFF
        self.n += 1

    def u8(self, v):
        self._put(v)

    def i8(self, v):
        self._put(v)

    def u16(self, v):
        self._put(v)
        self._put(v >> 8)

    def u32(self, v):
        for s in (0, 8, 16, 24):
            self._put(v >> s)

    def fixed(self, s, n):
        b = s.encode("utf-8")[:n]
        for x in b:
            self._put(x)
        for _ in range(n - len(b)):
            self._put(0)

    def data(self):
        return bytes(self.d[:self.n])


def main():
    # 1) 0x080 PlayerInput：头部 7B + 3帧×5B + baseline 8B = 30B
    w = W()
    w.u32(12345)
    w.u16(300)
    w.u8(3)
    for m, y, a, b in [(100, 0, 16384, 2), (80, 0, 0, 0), (0, 0, 0, 0)]:
        w.i8(m)
        w.i8(y)
        w.u16(a)
        w.u8(b)
    w.u32(100)
    w.u32(200)
    d = w.data()
    assert len(d) == 30, f"PlayerInput={len(d)}B 期望 30B"
    assert d[7] == 100 and d[22] == 100 and d[26] == 200, "字段错位"

    # 2) UDP 包头 16B：MAGIC 0x5A50 小端在开头（无前导 0）
    h = W()
    h.u16(0x5A50)
    h.u8(1)
    h.u8(0)
    h.u32(0x11223344)
    h.u16(7)
    h.u16(3)
    h.u32(0)
    hd = h.data()
    assert len(hd) == 16, f"包头={len(hd)}B 期望 16B"
    assert hd[0] == 0x50 and hd[1] == 0x5A, f"MAGIC 错位 {hd[:2].hex()}"
    assert hd[8:10] == b"\x07\x00", "seq 错位"

    # 3) 0x0C0 Snapshot：头部 7B + 4玩家×14B = 63B
    s = W()
    s.u32(50)
    s.u16(42)
    s.u8(4)
    for i in range(4):
        s.u8(i + 1)
        s.u16(1000 + i)
        s.u16(1000 + i)
        s.i8(0)
        s.i8(0)
        s.u16(0)
        s.u16(1000)
        s.u8(0)
        s.u8(100)
        s.u8(0)          # attackCdMs10（攻击冷却剩余 / 10ms）
    assert len(s.data()) == 63, f"Snapshot={len(s.data())}B 期望 63B"

    # 4) 0x040 MatchStart：头部 13B + 4玩家×22B = 101B
    m = W()
    m.u16(1)
    m.u32(0)
    m.u32(3600)
    m.u8(96)
    m.u8(96)
    m.u8(4)
    for i in range(4):
        m.u8(i + 1)
        m.u8(i)
        m.fixed("食材%d" % i, 16)
        m.u16(1000)
        m.u16(1000)
    assert len(m.data()) == 101, f"MatchStart={len(m.data())}B 期望 101B"

    # 5) 0x0C3 TerritoryKeyframe：serverTick u32 + runCount u16 + run{length u16, owner u8} = 9B
    k = W()
    k.u32(0)
    k.u16(1)
    k.u16(96)
    k.u8(0)
    assert len(k.data()) == 9, f"keyframe={len(k.data())}B 期望 9B"

    print("✅ 协议字节布局验证通过：PlayerInput=30B / UDP包头=16B / Snapshot=63B / MatchStart=101B / keyframe=9B")
    sys.exit(0)


if __name__ == "__main__":
    main()
