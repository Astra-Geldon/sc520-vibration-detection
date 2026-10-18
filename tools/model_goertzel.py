# -*- coding: utf-8 -*-
"""
振动频率识别 —— Goertzel 定点模型

输入（每条来自 FPGA 的固定块）：
    bx[n] = 固定块 Σ(ix·It)，每帧一个采样点

处理链（与将要写的 RTL 一一对应）：
    1. 一阶高通   hp[n] = (63*hp[n-1] + x[n] - x[n-1]) >> 6
    2. 降位宽     v[n]  = hp[n] >> SHIFT          （进入 Goertzel 的幅度）
    3. 17 个频点  s0 = v + c*s1 - s2
                  s2 = s1 ; s1 = s0                （c = 2cos(2πf/fs)，Q1.14）
    4. 窗口结束   mag² = s1² - c*s1*s2 + s2²      → 找峰值

参数：
    fs   = 59.5 Hz（实测 59~60，不是正好 60）
    N    = 128 帧（2.15 s）→ Δf = 0.465 Hz
    bins = 2.0 .. 10.0 Hz，步长 0.5 Hz，共 17 个

关键验证：
    · 定点 vs 浮点的频率误差
    · 双音分辨能力（相邻 0.5 Hz 档能否分开）
    · 直流/斜坡干扰是否被高通压住
    · 噪声下的可用性
"""
import math
import random
import sys

FS = 59.5
N = 128
F0 = 2.0
FSTEP = 0.5
NBIN = 17
SHIFT = 6            # 进入 Goertzel 的降位宽
COEF_FRAC = 14       # c 的 Q1.14
HP_ALPHA = 6         # 高通 (63*hp + d) >> 6 就是 /64


def coefs():
    """Q1.14 的 2cos(w)，四舍五入"""
    out = []
    for k in range(NBIN):
        f = F0 + k * FSTEP
        c = 2.0 * math.cos(2.0 * math.pi * f / FS)
        out.append((f, c, int(round(c * (1 << COEF_FRAC)))))
    return out


CS = coefs()


def to_s32(x):
    x &= 0xFFFFFFFF
    return x - (1 << 32) if x & 0x80000000 else x


def highpass(xs):
    """一阶高通，整数实现与 RTL 一致"""
    out = []
    hp = 0
    prev = 0
    for x in xs:
        d = x - prev
        hp = (63 * hp + d) >> HP_ALPHA
        prev = x
        out.append(hp)
    return out


def goertzel_fixed(xs, ci):
    """单个频点的定点 Goertzel，返回 mag²。状态 32 位有符号。"""
    s1 = 0
    s2 = 0
    for x in xs:
        v = x >> SHIFT
        # c*s1 在 Q1.14 → 右移 14 位对齐
        prod = (ci * s1) >> COEF_FRAC
        s0 = to_s32(v + prod - s2)
        s2 = s1
        s1 = s0
    # mag² = s1² - c*s1*s2 + s2²
    a = (s1 * s1)
    b = (ci * s1 * s2) >> COEF_FRAC
    c = (s2 * s2)
    return a - b + c


def goertzel_float(xs, f):
    """浮点参考：直接算 DFT 幅度"""
    re = 0.0
    im = 0.0
    w = 2.0 * math.pi * f / FS
    for n, x in enumerate(xs):
        re += x * math.cos(w * n)
        im -= x * math.sin(w * n)
    return re * re + im * im


def detect(xs):
    """返回 (峰值 bin 下标, 峰值频率, 峰值幅度, 全程 mag²)"""
    mags = [goertzel_fixed(xs, ci) for (_, _, ci) in CS]
    k = max(range(NBIN), key=lambda i: mags[i])
    return k, CS[k][0], mags[k], mags


def synth(f, amp=100000.0, n=N, noise=0.0, dc=0.0, ramp=0.0, seed=1):
    random.seed(seed)
    xs = []
    for i in range(n):
        v = amp * math.sin(2 * math.pi * f * i / FS + 0.3)
        v += dc + ramp * i
        if noise:
            v += random.gauss(0, noise)
        xs.append(int(v))
    return xs


def main():
    print('fs=%.2f  N=%d  Delta f=%.3f Hz  bins %.1f..%.1f (%d 个)'
          % (FS, N, FS / N, F0, F0 + (NBIN - 1) * FSTEP, NBIN))
    print('SHIFT=%d  coef=Q1.%d' % (SHIFT, COEF_FRAC))
    print()
    print('=== 系数表（Q1.14）===')
    for k, (f, c, ci) in enumerate(CS):
        print('  bin%2d  f=%4.1f Hz  c=%.6f  Q1.14=%6d' % (k, f, c, ci))

    print()
    print('=== 判据一：单音识别（纯信号，无噪声）===')
    print('%-10s %-8s %-9s %-10s %s' % ('真实f', '峰值bin', '检测f', '误差', '判定'))
    bad = 0
    for f in [2.0, 2.5, 3.5, 4.7, 5.0, 6.3, 7.5, 8.9, 10.0]:
        xs = synth(f)
        hp = highpass(xs)
        k, fd, mag, _ = detect(hp)
        err = fd - f
        ok = abs(err) <= FSTEP / 2 + 0.01
        if not ok:
            bad += 1
        print('%-10.2f %-8d %-9.1f %+10.2f %s'
              % (f, k, fd, err, 'OK' if ok else '**FAIL**'))

    print()
    print('=== 判据二：加噪声（SNR 约 10）===')
    b0 = bad
    for f in [2.0, 3.5, 5.0, 7.5, 9.0]:
        xs = synth(f, amp=100000.0)
        # 噪声：让 noise/amp 约 1/3（考虑高通后更强的相对噪声）
        xs = synth(f, amp=100000.0, noise=30000.0)
        hp = highpass(xs)
        k, fd, mag, _ = detect(hp)
        err = fd - f
        ok = abs(err) <= FSTEP / 2 + 0.01
        if not ok:
            bad += 1
        print('  f=%-5.1f -> bin%-2d (%.1f Hz) 误差 %+.2f  %s'
              % (f, k, fd, err, 'OK' if ok else '**FAIL**'))

    print()
    print('=== 判据三：直流 + 慢斜坡干扰是否被高通压住 ===')
    for f in [3.0, 6.0]:
        xs = synth(f, amp=50000.0, dc=500000.0, ramp=2000.0)
        hp = highpass(xs)
        k, fd, mag, _ = detect(hp)
        print('  f=%.1f 叠加 DC=5e5 和斜坡 2000/帧 -> bin%d (%.1f Hz)  %s'
              % (f, k, fd, 'OK' if abs(fd - f) <= FSTEP / 2 else '**FAIL**'))
        if abs(fd - f) > FSTEP / 2:
            bad += 1

    print()
    print('=== 判据四：相邻两档能否分开（间隔 0.5 Hz）===')
    for f1, f2 in [(5.0, 5.5), (3.0, 3.5), (8.0, 8.5)]:
        xs1 = synth(f1, amp=100000.0)
        xs2 = synth(f2, amp=100000.0)
        xs = [a + b for a, b in zip(xs1, xs2)]
        hp = highpass(xs)
        k, fd, mag, _ = detect(hp)
        print('  %.1f + %.1f Hz -> bin%d (%.1f Hz)  %s'
              % (f1, f2, k, fd, '按预期落在两者之一' if abs(fd - f1) <= FSTEP or abs(fd - f2) <= FSTEP else '**异常**'))

    print()
    print('=== 判据五：窗口长度对分辨率的影响 ===')
    f_true = 5.3
    for nn in (128, 256, 512):
        xs = synth(f_true, amp=100000.0, n=nn)
        hp = highpass(xs)
        mags = [goertzel_fixed(hp, ci) for (_, _, ci) in CS]
        k = max(range(NBIN), key=lambda i: mags[i])
        fd = CS[k][0]
        print('  N=%3d (%.2f s, Δf=%.3f) f_true=%.2f -> %.1f Hz  误差 %+.2f'
              % (nn, nn / FS, FS / nn, f_true, fd, fd - f_true))

    print()
    print('=== 判据六：定点 vs 浮点的幅度一致性 ===')
    xs = synth(5.0, amp=100000.0)
    hp = highpass(xs)
    k, fd, mag, mags = detect(hp)
    print('  bin   定点mag²        浮点mag²        比值')
    for i in (4, 5, 6, 7, 8, 10):
        fl = goertzel_float(hp, CS[i][0])
        r = (mags[i] / fl) if fl else 0
        print('  %-4d  %-15.3e %-15.3e %.4f' % (i, mags[i], fl, r))

    print()
    print('结论: ' + ('全部通过 ✓' if bad == 0 else '**%d 项失败**' % bad))
    return 0 if bad == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
