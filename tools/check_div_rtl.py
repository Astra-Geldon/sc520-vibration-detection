# -*- coding: utf-8 -*-
"""
逐位核对 vib_div_serial.v —— 严格按 RTL 的位宽和时序模拟。

和 model_serial_div.py 的区别：这里连**位宽**都照抄（49 位的 rem_sh / den_x、
48 位的 quot_sh、7 位计数器、done 脉冲），专门用来抓位宽和时序错误。
"""
import random
import sys

W = 48
DW = 32
LAST = W - 1
MASKW = (1 << W) - 1


class RTL:
    def __init__(self):
        self.quot_r = 0
        self.rem_r = 0
        self.den_r = 0
        self.cnt = 0
        self.busy = 0
        self.quot = 0
        self.rem = 0
        self.done = 0

    def step(self, start, numer, denom):
        # 组合
        rem_sh = ((self.rem_r << 1) | ((self.quot_r >> (W - 1)) & 1)) & ((1 << (W + 1)) - 1)
        quot_sh = (self.quot_r << 1) & MASKW
        den_x = self.den_r & ((1 << (W + 1)) - 1)          # 零扩展
        ge = 1 if rem_sh >= den_x else 0
        rem_next = (rem_sh - den_x) if ge else rem_sh
        quot_set = (quot_sh | 1) if ge else quot_sh

        # 时序
        self.done = 0
        if start:
            self.quot_r = numer & MASKW
            self.rem_r = 0
            self.den_r = denom & ((1 << DW) - 1)
            self.cnt = 0
            self.busy = 1
        elif self.busy:
            # ★ RTL 里是 cnt <= cnt+1 与 if (cnt == LAST) 同时用**旧的 cnt**
            #   （非阻塞赋值），所以先判断再自增，共 48 拍。
            #   写成"先自增再判断"会少一拍，商正好变成一半。
            if self.cnt == LAST:
                self.busy = 0
                self.done = 1
                self.quot = quot_set
                self.rem = rem_next & MASKW
            self.rem_r = rem_next & MASKW
            self.quot_r = quot_set
            self.cnt = (self.cnt + 1) & 0x7F

    def run(self, numer, denom, maxcyc=200):
        self.step(1, numer, denom)
        n = 1
        while not self.done:
            self.step(0, 0, 0)
            n += 1
            if n > maxcyc:
                raise RuntimeError('跑不完 numer=%d denom=%d' % (numer, denom))
        return self.quot, self.rem, n


def check(a, b):
    r = RTL()
    q, rem, n = r.run(a, b)
    if b == 0:
        return True, q, rem, n           # 除零只要求"不卡死"
    return (q == a // b and rem == a % b), q, rem, n


def main():
    bad = 0
    print('=== 边界 ===')
    # 被除数用满 48 位；除数必须 <= 2^32-1（RTL 的 denom 端口只有 32 位）
    avals = [0, 1, 2, 15, 255, 256, 1024, 4800, (1 << 24) - 1, (1 << 31) - 1,
             (1 << 31), (1 << 47), (1 << 47) - 1, (1 << 48) - 1]
    bvals = [0, 1, 2, 15, 255, 256, 1024, 4800, 65535, (1 << 24),
             (1 << 31) - 1, (1 << 31)]
    cyc = set()
    for a in avals:
        for b in bvals:
            ok, q, rem, n = check(a, b)
            cyc.add(n)
            if not ok:
                bad += 1
                if bad <= 5:
                    print('  FAIL a=%d b=%d got q=%s rem=%s want q=%s rem=%s'
                          % (a, b, q, rem, a // b, a % b))
    print('  %d 组，失败 %d，拍数集合 %s'
          % (len(avals) * len(bvals), bad, sorted(cyc)))

    print()
    print('=== 随机 80000 组 ===')
    random.seed(17)
    b0 = bad
    for _ in range(80000):
        a = random.getrandbits(random.randint(1, 48))
        b = random.getrandbits(random.randint(1, 32))
        ok, q, rem, n = check(a, b)
        if not ok:
            bad += 1
            if bad - b0 <= 5:
                print('  FAIL a=%d b=%d got=%s want=%s' % (a, b, q, a // b))
    print('  失败 %d' % (bad - b0))

    print()
    print('=== 我们实际量级 ===')
    b0 = bad
    for _ in range(30000):
        den = random.randint(1024, (1 << 31) - 1)
        q_want = random.randint(0, 40000)
        num = min(den * q_want + random.randint(0, den - 1), (1 << 48) - 1)
        ok, q, rem, n = check(num, den)
        if not ok:
            bad += 1
    print('  失败 %d' % (bad - b0))

    print()
    print('=== 除零不卡死 ===')
    for b in (0,):
        r = RTL()
        q, rem, n = r.run(12345, b)
        print('  12345/0 -> q=0x%X rem=%d 用了 %d 拍  %s'
              % (q, rem, n, 'OK(不卡死)' if n < 200 else 'FAIL'))

    print()
    print('结论: ' + ('RTL 与模型一致 ✓' if bad == 0 else '**有错**'))
    return 0 if bad == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
