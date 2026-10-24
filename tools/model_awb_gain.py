# -*- coding: utf-8 -*-
"""AWB异常统计路径的离线模型。

用于验证本次RTL防护的量级，不替代板上采集：
1. 旧逻辑在分母接近1时会把R增益推到约16倍；
2. 旧逻辑的帧间平滑会让异常增益持续多帧；
3. 新逻辑在样本不足时保持旧增益，并把有效帧增益限制在0.5x~2.0x。
"""

Q = 16
GAIN_MIN = 0x08000
GAIN_MAX = 0x20000
MIN_SAMPLES = 4096


def old_gain(sum_g, sum_r):
    """模拟旧RTL的(G/R)Q16和16x上限。"""
    q = (sum_g << Q) // max(sum_r, 1)
    return min(q, 0xFFFFF)


def new_gain(sum_g, sum_r, sample_count, old):
    """模拟新RTL：样本不足保持旧值，正常计算后限幅。"""
    if sample_count < MIN_SAMPLES:
        return old
    q = old_gain(sum_g, sum_r)
    return max(GAIN_MIN, min(q, GAIN_MAX))


def q16(x):
    return x / float(1 << Q)


def main():
    # 过滤后只有很少样本，R累加器接近初始化值1，G仍有较大累加。
    bad_sum_r = 1
    bad_sum_g = 100 * MIN_SAMPLES

    first = old_gain(bad_sum_g, bad_sum_r)
    old_seq = [first]
    for _ in range(5):
        old_seq.append((3 * old_seq[-1] + (1 << Q)) // 4)

    fixed = new_gain(bad_sum_g, bad_sum_r, MIN_SAMPLES - 1, 1 << Q)
    clipped = new_gain(bad_sum_g, bad_sum_r, MIN_SAMPLES, 1 << Q)

    print('旧逻辑异常首帧R增益: %.4fx (Q16=0x%05x)' % (q16(first), first))
    print('旧逻辑后续平滑增益: ' + ', '.join('%.4fx' % q16(x) for x in old_seq))
    print('新逻辑样本不足: %.4fx' % q16(fixed))
    print('新逻辑样本充足但比例异常后限幅: %.4fx' % q16(clipped))

    assert first == 0xFFFFF
    assert fixed == (1 << Q)
    assert clipped == GAIN_MAX
    assert old_seq[1] > 8 * (1 << Q)
    print('结论: 异常增益路径和样本保护均符合预期。')


if __name__ == '__main__':
    main()
