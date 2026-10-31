"""Regenerate only N1/N2 Q8 coefficients, preserving archived L1 exactly.

No image fitting: knots are input/output RGB-peak code values. Output artifacts
belong in --output. The real RTL is checked separately by test_natural_lift.py.
"""
from fractions import Fraction
from pathlib import Path
import argparse
import csv
import hashlib
import json
import re


KNOTS = [(0, 0, 0), (16, 28, 40), (32, 52, 72), (64, 100, 124),
         (96, 136, 156), (128, 160, 176), (160, 176, 184),
         (192, 192, 192), (255, 255, 255)]


def nearest(value):
    return (2 * value.numerator + value.denominator) // (2 * value.denominator)


def target(peak, profile):
    for left, right in zip(KNOTS, KNOTS[1:]):
        if left[0] <= peak <= right[0]:
            return nearest(Fraction(left[profile]) +
                           Fraction((peak - left[0]) * (right[profile] - left[profile]),
                                    right[0] - left[0]))
    raise ValueError(peak)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    path = root / 'user_source/hdl_source/highlight_tone.v'
    text = path.read_text(encoding='utf-8')
    before, lut = text.split('module gain8_lift_gain(', 1)
    rows = []

    def entry(match):
        peak = int(match[1])
        l1 = (int(match[2], 16) >> 22) & 2047
        gains = [256 if peak == 0 else nearest(Fraction(256 * target(peak, n), peak))
                 for n in [1, 2]]
        if peak >= 192:
            gains = [256, 256]
        outputs = [(peak * gain + 128) >> 8 for gain in gains]
        assert outputs == [target(peak, n) for n in [1, 2]]
        assert all(256 <= gain <= 2047 for gain in gains)
        rows.append([peak, (peak * l1 + 128) >> 8, *outputs, *gains])
        packed = (l1 << 22) | (gains[0] << 11) | gains[1]
        return f"8'd{peak}: values=33'h{packed:09x}"

    lut, count = re.subn(r"8'd(\d+):\s*values=33'h([0-9a-fA-F]+)", entry, lut)
    assert count == 256
    for column in [2, 3]:
        assert all(a[column] <= b[column] for a, b in zip(rows, rows[1:]))
    before = before.replace(
        '// rounded peak targets. L1 preserves the G12 reference; L2/N1 and L3/N2\n'
        '// restore mild/medium non-highlight contrast. Peak>=208 equals L1 in all\n'
        '// three profiles. No RGB9 shoulder, channel LUTs, DSP or frame processing.',
        '// rounded peak targets. L1 preserves the old G12 reference; N1/N2 lift\n'
        '// only mid-dark pixels and return to exact unity at peak>=192. N2 lifts\n'
        '// shadows more strongly, with a flatter shoulder. Common RGB scaling;\n'
        '// no RGB9 shoulder, channel LUTs, DSP or frame processing.')
    result = before + 'module gain8_lift_gain(' + lut
    args.output.mkdir(parents=True, exist_ok=True)
    with (args.output / 'curves.csv').open('w', newline='', encoding='utf-8') as stream:
        writer = csv.writer(stream)
        writer.writerow(['input_peak', 'old_L1', 'new_N1', 'new_N2', 'N1_Q8', 'N2_Q8'])
        writer.writerows(rows)
    summary = {'knots_p_N1_N2': KNOTS, 'highlight_input_peak_threshold': 192,
               'highlight_gain_Q8': 256, 'L1_coefficients_preserved': True,
               'new_peak_targets_monotone': True,
               'N1_N2_max_difference_codes': max(r[3] - r[2] for r in rows),
               'source_sha256_after': hashlib.sha256(result.encode('utf-8')).hexdigest()}
    (args.output / 'curve_design.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    if args.write:
        path.write_text(result, encoding='utf-8', newline='\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
