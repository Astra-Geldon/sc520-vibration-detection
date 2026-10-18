# -*- coding: utf-8 -*-
"""
串行恢复余数除法器 —— 逐位模型（48 位 / 32 位）

结构（经典教科书版，恒定 48 拍）：
    被除数放进 quot，rem = 0
    每拍： (rem, quot) 一起左移一位（被除数的 MSB 移进 rem 的最低位）
           if rem >= den: rem -= den; quot[0] = 1

这个模型就是 RTL 的唯一依据：RTL 写完后按同一结构逐行对照。
"""
import random
import sys

W = 48          # 被除数 / 商 位宽
DW = 32         # 除数位宽
MASK = (1 << W) - 1


def div_step(rem, quot, den):
    """一拍。返回下一拍的值。"""
    # 被除数最高位（quot 的 MSB）移进 rem
    bit = (quot >> (W - 1)) & 1
    rem2 = ((rem << 1) | bit)
    quot2 = (quot << 1) & MASK
    if rem2 >= den:
        rem2 -= den
        quot2 |= 1
    return rem2, quot2


def div_hw(numer, denom):
    """完整一次除法，返回 (quot, rem)"""
    rem = 0
    quot = numer & MASK
    for _ in range(W):
        rem, quot = div_step(rem, quot, denom)
    return quot, rem


def check(numer, denom):
    q, r = div_hw(numer, denom)
    if denom == 0:
        return True, None, None          # 除零不校验
    return (q == numer // denom and r == numer % denom), q, r


def main():
    bad = 0

    print('=== 边界穷举 ===')
    vals = [0, 1, 2, 3, 15, 255, 256, 4800, 4801,
            (1 << 24), (1 << 24) - 1, (1 << 31) - 1, (1 << 31),
            (1 << 47), (1 << 47) - 1, (1 << 48) - 1]
    for a in vals:
        for b in vals:
            ok, q, r = check(a, b)
            if not ok:
                bad += 1
                if bad <= 5:
                    print('  FAIL a=%d b=%d got q=%s want=%s' % (a, b, q, a // b))
    print('  组合 %d 组，失败 %d' % (len(vals) ** 2, bad))

    print()
    print('=== 随机 100000 组（全 48 位范围）===')
    random.seed(5)
    b0 = bad
    for _ in range(100000):
        a = random.getrandbits(random.randint(1, 48))
        b = random.getrandbits(random.randint(1, 48))
        ok, q, r = check(a, b)
        if not ok:
            bad += 1
            if bad - b0 <= 5:
                print('  FAIL a=%d b=%d got=%s want=%s' % (a, b, q, a // b))
    print('  失败 %d' % (bad - b0))

    print()
    print('=== 我们实际量级：num48 / den32（den >= 1024）===')
    b0 = bad
    worst = 0
    for _ in range(50000):
        den = random.randint(1024, (1 << 31) - 1)
        q_want = random.randint(0, 40000)
        num = min(den * q_want + random.randint(0, den - 1), (1 << 48) - 1)
        ok, q, r = check(num, den)
        if not ok:
            bad += 1
    print('  失败 %d' % (bad - b0))

    print()
    print('=== 关键边界 ===')
    for a, b, note in [(0, 1, 'numer=0'), (1, 1, 'a=b=1'), (1, (1 << 48) - 1, 'a<b'),
                       ((1 << 48) - 1, 1, 'div by 1'), ((1 << 48) - 1, (1 << 31) - 1, 'max'),
                       (1 << 47, 1 << 31, 'pow2')]:
        ok, q, r = check(a, b)
        print('  %-14s a=%-14d b=%-12d q=%s  %s'
              % (note, a, b, q, 'OK' if ok else '**FAIL**'))
        if not ok:
            bad += 1

    print()
    print('结论: ' + ('模型正确 ✓ 可以据此写 RTL' if bad == 0 else '**模型有错**'))
    return 0 if bad == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
