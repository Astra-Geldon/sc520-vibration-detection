"""Recovery source checks and fixed-point arithmetic model (not RTL).

This is NOT an RTL simulation. The coefficient and Hz10 expressions are read
from the actual multi/peak source files. The model covers the per-block high
pass, 32-bit recurrence, saturation and peak energy arithmetic; it does not
simulate ERAM timing, control, CDC, candidate sorting or target confirmation.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import random
import re

FS = 59.5
NFRM = 64
NBIN = 17
NBLOCK = 48
MAG_SH = 8
TONE_RATIO = 0


def signed(value: int, bits: int) -> int:
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def source_coefficients(source: str) -> list[int]:
    match = re.search(r'function signed \[15:0\] coef_of;(.*?)endfunction', source, re.S)
    assert match, 'Missing coefficient function'
    return [int(v) for v in re.findall(r'coef_of\s*=\s*16\x27sd(\d+)', match.group(1))]


def eval_concat(expression: str, variable: str, value: int) -> int:
    """Evaluate only the unsigned literals/concatenations used for Hz10."""
    def atom(token: str) -> tuple[int, int]:
        token = token.strip()
        if token == variable:
            return value, 5
        match = re.fullmatch(r"(\d+)'([bdh])([0-9a-fA-F]+)", token)
        assert match, 'Unsupported source expression: ' + token
        width, base, digits = match.groups()
        return int(digits, {'b': 2, 'd': 10, 'h': 16}[base]), int(width)

    def concat(match: re.Match) -> str:
        total = 0
        for token in match.group(1).split(','):
            number, width = atom(token)
            total = (total << width) | (number & ((1 << width) - 1))
        return str(total)

    expression = re.sub(r'\{([^{}]+)\}', concat, expression)
    total = 0
    for term in expression.split('+'):
        term = term.strip()
        total += int(term) if term.isdecimal() else atom(term)[0]
    return total & 255


def spectrum(samples: list[int], coefficients: list[int], *, agc_gain: int = 0,
             previous_hp: int = 0, previous_x: int = 0) -> tuple[list[int], int, int]:
    s1, s2 = [0] * NBIN, [0] * NBIN
    hp, xp = previous_hp, previous_x
    shift = (6, 4, 2, 0)[min(agc_gain, 6) >> 1]
    for sample in samples:
        x = signed(sample, 32)
        hp = signed((52 * hp + x - xp) >> 6, 32)
        xp = x
        v = hp >> shift
        for k, coefficient in enumerate(coefficients):
            product = signed(coefficient * s1[k], 48)
            cs1 = signed(product >> 14, 32)
            wide = signed(v + cs1 - s2[k], 33)
            s0 = 1073741823 if wide > 1073741824 else max(-1073741824, wide)
            s2[k], s1[k] = s1[k], signed(s0, 32)
    energy = []
    for k, coefficient in enumerate(coefficients):
        cs1 = signed((coefficient * s1[k]) >> 14, 32)
        mag = signed(s1[k] * s1[k] - cs1 * s2[k] + s2[k] * s2[k], 64)
        energy.append(min((1 << 58) - 1, max(0, mag)))
    return energy, hp, xp


def peak_result(energy: list[int], aexp: int = 22) -> dict:
    k = max(range(NBIN), key=energy.__getitem__)
    scaled = [min((1 << 32) - 1, value >> MAG_SH) for value in energy]
    peak = scaled[k]
    rest = sum(scaled) - peak
    tonal = peak > 25 and peak * 7 > rest * 2
    # Texture normalization is diagnostic only, never an admission condition.
    return {'bin': k, 'hz10': 20 + 5*k, 'raw_peak': peak,
            'tonal': tonal, 'qualified': tonal}


def generate_samples(hz: float, amplitude: int, phase: float, noise: float,
                     rng: random.Random) -> list[int]:
    return [round(amplitude * (math.sin(2 * math.pi * hz * n / FS + phase)
                              + noise * rng.gauss(0, 1))) for n in range(NFRM)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    vib = args.root / 'user_source' / 'hdl_source' / 'vibration'
    multi = (vib / 'vib_gz_multi.v').read_text(encoding='utf-8')
    peak = (vib / 'vib_gz_peak.v').read_text(encoding='utf-8')
    coefficients = source_coefficients(multi)
    formula = [round(32768 * math.cos(2 * math.pi * (2 + .5 * k) / FS)) for k in range(NBIN)]
    assert coefficients == source_coefficients(peak) == formula
    assert re.search(r'parameter\s+NFRM\s*=\s*64\b', multi)
    assert re.search(r'parameter\s+NBIN\s*=\s*17\b', multi)
    assert re.search(r'parameter\s+NBIN\s*=\s*17\b', peak)
    assert re.search(r'parameter\s+BIN_MIN\s*=\s*0\b', peak)
    assert re.search(r'\bMAG_SH\s*=\s*8\b', peak)
    assert re.search(r"\bTONE_MIN\s*=\s*32'd25\b", peak)
    assert 'PN_FLOOR' not in re.sub(r'//[^\n]*', '', peak)
    hz_expr = re.search(r'hz_of\s*=\s*([^;]+);', peak).group(1)
    for k in range(NBIN):
        assert eval_concat(hz_expr, 'k', k) == 20+5*k
        assert 20 <= eval_concat(hz_expr, 'k', k) <= 100

    row_function = re.search(r'function \[9:0\] row_base;(.*?)endfunction', multi, re.S).group(1)
    row_bases = [int(v) for v in re.findall(r"row_base\s*=\s*10'd(\d+)", row_function)]
    assert row_bases == [r * 8 * NBIN for r in range(6)]
    addresses = [row_bases[r] + c * NBIN + k for r in range(6) for c in range(8) for k in range(NBIN)]
    assert sorted(addresses) == list(range(816))
    assert 'NROW * NCOL * NBIN' in multi
    assert "288230376151711743" in peak  # Nonnegative signed-59 energy bound.

    rng = random.Random(520)
    cases, results = 0, []
    for k in range(NBIN):
        for amplitude in (50_000, 150_000, 600_000):
            for phase in (0.0, 0.37, 1.2, 2.6):
                for noise in (0.0, 0.1):
                    energy, _, _ = spectrum(generate_samples(2 + .5 * k, amplitude, phase, noise, rng), coefficients)
                    result = peak_result(energy)
                    assert result['bin'] == k, (k, amplitude, phase, noise, result)
                    assert result['hz10'] <= 100
                    assert result['qualified'], (k, amplitude, result)
                    assert all(0 <= e <= (1 << 58) - 1 for e in energy)
                    cases += 1
                    if amplitude == 150_000 and phase == .37 and noise == .1:
                        results.append({'input_hz': 2 + .5 * k, **result})

    # All 48 blocks retain their own arithmetic state and known input identity.
    # This checks address coverage and independent arithmetic, not the RTL FSM.
    grid = []
    for block in range(NBLOCK):
        k = block % NBIN
        energy, _, _ = spectrum(generate_samples(2 + .5 * k, 150_000, .2 + block * .03, .1, rng), coefficients)
        result = peak_result(energy)
        assert result['bin'] == k, (block, result)
        grid.append({'block': block, **result})
    silent, _, _ = spectrum([0] * NFRM, coefficients)
    assert silent == [0] * NBIN
    assert not peak_result(silent)['qualified']
    # Explicit arithmetic stress: energy is nonnegative, even at state saturation.
    stress = [signed((1 << 31) - 1 if n & 1 else -(1 << 31), 32) for n in range(NFRM)]
    stress_energy, _, _ = spectrum(stress, coefficients, agc_gain=6)
    assert all(0 <= e <= (1 << 58) - 1 for e in stress_energy)
    # Reproduce the observed-scale rejection algebraically as a regression:
    # raw peak around897792 cannot survive the failed PN floor at AEXP22.
    board_like = [1024]*NBIN
    board_like[12] = 3507 << 8
    assert ((board_like[12] >> 2) >> 22) == 0
    assert peak_result(board_like, 22)['qualified']
    assert peak_result(board_like, 31)['qualified']
    report = {'verification': 'source static checks plus fixed-point arithmetic model; NOT RTL simulation',
              'fs_assumption_hz': FS, 'window_frames': NFRM, 'nbin': NBIN,
              'state_addresses': len(addresses), 'single_frequency_cases': cases,
              'grid_blocks': len(grid), 'frequency_examples': results,
              'limits': ['This script does not simulate ERAM/control/CDC',
                         'Separate Icarus scanner RTL regression covers target selection and confirmation',
                         'Hardware sampling rate and detection thresholds require board logs']}
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
