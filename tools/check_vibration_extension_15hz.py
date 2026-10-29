"""Static and fixed point checks for the active 2.0--15.0 Hz chain.

This is a source/model check, not a TD or RTL timing simulation.  It keeps the
legacy 17-point checker untouched and verifies the active 27-point chain that
is selected by ``design_top_wrapper.v``.
"""
from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
import random

FS = 59.5
NFRM = 64
NBIN = 27
NBLOCK = 48
EXPECTED = [round(32768 * math.cos(2 * math.pi * (2 + 0.5 * k) / FS))
            for k in range(NBIN)]


def signed(value: int, bits: int) -> int:
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def source_coefficients(source: str) -> list[int]:
    body = re.search(r"function signed \[15:0\] coef_of;(.*?)endfunction",
                     source, re.S)
    assert body, "missing coefficient function"
    found: dict[int, int] = {}
    for match in re.finditer(
            r"(?:5'd)?(\d+)\s*:\s*coef_of\s*=\s*(-?)16'sd(\d+)",
            body.group(1)):
        index, sign, magnitude = match.groups()
        found[int(index)] = (-1 if sign else 1) * int(magnitude)
    return [found[k] for k in range(NBIN)]


def spectrum(samples: list[int], coefficients: list[int]) -> list[int]:
    s1, s2 = [0] * NBIN, [0] * NBIN
    hp = xp = 0
    for sample in samples:
        x = signed(sample, 32)
        hp = signed((52 * hp + x - xp) >> 6, 32)
        xp = x
        value = hp >> 6
        for k, coefficient in enumerate(coefficients):
            cs1 = signed((coefficient * s1[k]) >> 14, 32)
            wide = signed(value + cs1 - s2[k], 33)
            if wide > 1073741824:
                state = 1073741823
            elif wide < -1073741824:
                state = -1073741824
            else:
                state = wide
            s2[k], s1[k] = s1[k], signed(state, 32)

    energies = []
    for k, coefficient in enumerate(coefficients):
        cs1 = signed((coefficient * s1[k]) >> 14, 32)
        magnitude = signed(s1[k] * s1[k] - cs1 * s2[k] + s2[k] * s2[k], 64)
        energies.append(max(0, min((1 << 58) - 1, magnitude)))
    return energies


def samples(frequency: float, amplitude: int, noise: float, rng: random.Random) -> list[int]:
    return [round(amplitude * (
        math.sin(2 * math.pi * frequency * n / FS + 0.37)
        + noise * rng.gauss(0, 1))) for n in range(NFRM)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    hdl = args.root / 'user_source' / 'hdl_source'
    multi_path = hdl / 'vibration' / 'vib_gz_multi.v'
    peak_path = hdl / 'vibration' / 'vib_gz_peak.v'
    multi = multi_path.read_text(encoding='utf-8')
    peak = peak_path.read_text(encoding='utf-8')
    top = (hdl / 'design_top_wrapper.v').read_text(encoding='utf-8')
    osd = (hdl / 'vibration' / 'vib_osd_marker.v').read_text(encoding='utf-8')
    uart = (hdl / 'uart_log_debug.v').read_text(encoding='utf-8')

    assert source_coefficients(multi) == EXPECTED
    assert source_coefficients(peak) == EXPECTED
    assert re.search(r'parameter\s+NFRM\s*=\s*64\b', multi)
    assert re.search(r'parameter\s+NBIN\s*=\s*27\b', multi)
    assert re.search(r'parameter\s+NBIN\s*=\s*27\b', peak)
    assert len(re.findall(r'\.NBIN\(27\)', top)) == 2
    assert '48*27 = 1296' in multi
    assert '125:hz_digits=12\'h125' in osd
    assert '150:hz_digits=12\'h150' in osd
    assert '32\'h0002_000A' in uart and '0x510' in uart

    addresses = [row * 8 * NBIN + column * NBIN + k
                 for row in range(6) for column in range(8) for k in range(NBIN)]
    assert sorted(addresses) == list(range(48 * 27))

    rng = random.Random(520)
    cases = []
    for k in range(NBIN):
        frequency = 2 + 0.5 * k
        energies = spectrum(samples(frequency, 150_000, 0.0, rng), EXPECTED)
        peak_bin = max(range(NBIN), key=energies.__getitem__)
        assert peak_bin == k, (frequency, peak_bin)
        cases.append({'frequency_hz': frequency, 'bin': peak_bin,
                      'hz10': 20 + 5 * peak_bin})

    noisy_cases = 0
    for k in (0, 2, 7, 12, 20, 21, 23, 26):
        frequency = 2 + 0.5 * k
        energies = spectrum(samples(frequency, 150_000, 0.10, rng), EXPECTED)
        assert max(range(NBIN), key=energies.__getitem__) == k
        noisy_cases += 1

    report = {
        'range_hz': [2.0, 15.0], 'step_hz': 0.5, 'bins': NBIN,
        'state_words': len(addresses), 'window_frames': NFRM,
        'coefficient_formula': 'round(32768*cos(2*pi*f/59.5))',
        'pure_cases': cases, 'noisy_cases': noisy_cases,
        'scope': 'source checks and fixed-point model; no TD/timing/board result',
    }
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
