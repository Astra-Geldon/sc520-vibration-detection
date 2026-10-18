# -*- coding: utf-8 -*-
"""逐位核对 vib_goertzel.v —— 严格按 RTL 的位宽、舍入和顺序模拟。"""
import math
import random
import sys

FS = 59.5
NBIN = 17
NFRM = 128
COEF_FRAC = 14
LAST_FRM = NFRM - 1

COEFS = [32040, 31633, 31137, 30555, 29888, 29137, 28306, 27395, 26408,
         25347, 24216, 23017, 21754, 20431, 19050, 17616, 16134]


def s32(x):
    x &= 0xFFFFFFFF
    return x - (1 << 32) if x & 0x80000000 else x


def s64(x):
    x &= 0xFFFFFFFFFFFFFFFF
    return x - (1 << 64) if x & 0x8000000000000000 else x


class RTL(object):
    def __init__(self):
        self.gst = 'CLR'
        self.s1 = [0] * NBIN
        self.s2 = [0] * NBIN
        self.hp = 0
        self.xprev = 0
        self.bidx = 0
        self.fcnt = 0
        self.clr_i = 0
        self.rd1 = 0
        self.rd2 = 0
        self.ccur = 0
        self.vcur = 0
        self.pmax = 0
        self.pidx = 0
        self.peak_bin = 0
        self.peak_hz10 = 0
        self.peak_mag = 0
        self.valid = 0
        self.frm_cnt = 0
        self.nclk = 0

    def tick_in(self, tick, bx):
        self.nclk += 1
        self.valid = 0
        cs1 = (self.ccur * self.rd1) >> COEF_FRAC
        s0 = s32(self.vcur + s32(cs1) - self.rd2)
        sq1 = self.rd1 * self.rd1
        sq2 = self.rd2 * self.rd2
        cs12 = (self.ccur * self.rd1 * self.rd2) >> COEF_FRAC
        mag2 = s64(sq1 - cs12 + sq2)
        hp_next = s32(((self.hp * 63) + (bx - self.xprev)) >> 6)

        g = self.gst
        if g == 'CLR':
            self.s1[self.clr_i] = 0
            self.s2[self.clr_i] = 0
            if self.clr_i == NBIN - 1:
                self.clr_i = 0
                self.gst = 'G_IDLE'
            else:
                self.clr_i += 1
        elif g == 'G_IDLE':
            if tick:
                self.hp = hp_next
                self.xprev = bx
                self.vcur = hp_next >> 6
                self.bidx = 0
                self.gst = 'G_READ'
        elif g == 'G_READ':
            self.rd1 = self.s1[self.bidx]
            self.rd2 = self.s2[self.bidx]
            self.ccur = COEFS[self.bidx]
            self.gst = 'G_CALC'
        elif g == 'G_CALC':
            self.s1[self.bidx] = s0
            self.s2[self.bidx] = self.rd1
            if self.bidx == NBIN - 1:
                self.bidx = 0
                if self.fcnt == LAST_FRM:
                    self.frm_cnt = (self.frm_cnt + 1) & 0xFF
                    self.gst = 'P_READ'
                else:
                    self.fcnt = (self.fcnt + 1) & 0xFF
                    self.frm_cnt = (self.frm_cnt + 1) & 0xFF
                    self.gst = 'G_IDLE'
            else:
                self.bidx += 1
                self.gst = 'G_READ'
        elif g == 'P_READ':
            self.rd1 = self.s1[self.bidx]
            self.rd2 = self.s2[self.bidx]
            self.ccur = COEFS[self.bidx]
            self.gst = 'P_CALC'
        elif g == 'P_CALC':
            if mag2 >= 0 and mag2 > self.pmax:
                self.pmax = mag2
                self.pidx = self.bidx
            if self.bidx == NBIN - 1:
                self.bidx = 0
                self.gst = 'P_DONE'
            else:
                self.bidx += 1
                self.gst = 'P_READ'
        elif g == 'P_DONE':
            self.peak_bin = self.pidx
            self.peak_hz10 = (20 + (self.pidx << 2) + self.pidx) & 0xFF
            self.peak_mag = self.pmax
            self.valid = 1
            self.pmax = 0
            self.pidx = 0
            self.fcnt = 0
            self.frm_cnt = 0
            self.clr_i = 0
            self.gst = 'CLR'
        return self.valid


def run(bxs):
    r = RTL()
    nclk = 0
    guard = 0
    while r.gst != 'G_IDLE':
        nclk += 1
        r.tick_in(0, 0)
        guard += 1
        if guard > 10000:
            raise RuntimeError('CLR 跑不完')
    for x in bxs:
        if r.gst != 'G_IDLE':
            raise RuntimeError('送 tick 时不在 G_IDLE: ' + r.gst)
        nclk += 1
        r.tick_in(1, x)
        guard = 0
        while r.gst != 'G_IDLE':
            nclk += 1
            r.tick_in(0, 0)
            guard += 1
            if guard > 10000:
                raise RuntimeError('一拍处理跑不完: ' + r.gst)
    return (r.peak_bin, r.peak_hz10, r.peak_mag, nclk)


def synth(f, amp=100000.0, n=NFRM, noise=0.0, seed=7):
    random.seed(seed)
    out = []
    for i in range(n):
        v = amp * math.sin(2 * math.pi * f * i / FS + 0.3)
        if noise:
            v += random.gauss(0, noise)
        out.append(int(v))
    return out


def main():
    bad = 0
    print('=== 判据一：peak_hz10 编码（20 + 5k）===')
    for k in range(NBIN):
        got = (20 + (k << 2) + k) & 0xFF
        want = (20 + 5 * k) & 0xFF
        if got != want:
            bad += 1
    print('  17 个频点 %s' % ('全部正确 ✓' if bad == 0 else '**有错**'))

    print()
    print('=== 判据二：整机识别（128 帧窗口，纯信号）===')
    print('%-9s %-6s %-6s %-14s %s' % ('真实f', 'bin', 'hz10', 'peak_mag', '判定'))
    for f in [2.0, 2.5, 3.5, 5.0, 6.5, 8.0, 10.0]:
        xs = synth(f)
        pb, hz, mag, nclk = run(xs)
        err = hz / 10.0 - f
        ok = abs(err) <= 0.25 + 1e-6
        if not ok:
            bad += 1
        print('%-9.2f %-6d %-6d %-14d %s'
              % (f, pb, hz, mag, 'OK' if ok else '**FAIL %+.2f**' % err))

    print()
    print('=== 判据三：加噪声（幅度 3e4 vs 信号 1e5）===')
    b0 = bad
    for f in [3.0, 5.0, 7.5]:
        xs = synth(f, noise=30000.0)
        pb, hz, mag, nclk = run(xs)
        ok = abs(hz / 10.0 - f) <= 0.25 + 1e-6
        if not ok:
            bad += 1
        print('  f=%-5.1f -> bin%-2d hz10=%-4d %s' % (f, pb, hz, 'OK' if ok else '**FAIL**'))

    print()
    print('=== 判据四：拍数预算 ===')
    xs = synth(5.0)
    pb, hz, mag, nclk = run(xs)
    print('  128 帧窗口共 %d 拍，平均 %.1f 拍/帧' % (nclk, nclk / float(NFRM)))
    print('  一帧 1,240,000 拍 → 占用 %.2f%%' % (100.0 * (nclk / float(NFRM)) / 1240000.0))

    print()
    print('结论: ' + ('RTL 逻辑一致 ✓' if bad == 0 else '**%d 项失败**' % bad))
    return 0 if bad == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
