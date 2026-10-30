"""Independent numeric oracle and complete720p streaming RTL verification.

Does not open a camera, program the FPGA, or modify production parameters.
RAM simulation uses an explicit synchronous NOREG model; encrypted vendor RAM
simulation is unavailable in Icarus. Physical implementation is checked by TD.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import random
import subprocess


PARAMS = {1: (8, 12, 1, 2), 2: (12, 16, 2, 4), 3: (16, 24, 3, 6)}


def token(rgb, meta, de=1, protect=0, hs=0, vs=0):
    r, g, b = rgb
    y = (77*r+150*g+29*b+128)//256
    return ((meta << 30) | (hs << 29) | (vs << 28) | (de << 27) |
            (protect << 26) | (y << 18) | (((r-g) & 511) << 9) | ((b-g) & 511))


def unpack(t):
    dr, db = (t >> 9) & 511, t & 511
    return (t >> 18) & 255, dr-512 if dr >= 256 else dr, db-512 if db >= 256 else db


def reference(words):
    """Wide Python integers specify math, independent of RTL widths/pipeline."""
    c = words[4]
    meta = c >> 30
    flags = (c >> 27) & 7
    mode = (meta >> 12) & 7
    y, cr, cb = unpack(c)
    old_g = y - (77*cr+29*cb+128)//256
    old = (old_g+cr, old_g, old_g+cb)
    assert all(0 <= ch <= 255 for ch in old)
    if not (flags & 1):
        return (meta << 27) | (flags << 24), "blank"
    status = "bypass"
    result = old
    if mode in PARAMS and not ((c >> 26) & 1) and all((n >> 27) & 1 for n in words):
        yt, ct, strength, cap = PARAMS[mode]
        rsum = bsum = 0
        for weight, n in zip((1, 2, 1, 2, 4, 2, 1, 2, 1), words):
            ny, nr, nb = unpack(n)
            valid = not ((n >> 26) & 1) and (n >> 30) == meta
            valid = valid and abs(ny-y) <= yt and abs(nr-cr) <= ct and abs(nb-cb) <= ct
            rsum += weight*(nr if valid else cr)
            bsum += weight*(nb if valid else cb)
        ar, ab = (rsum+8)//16, (bsum+8)//16
        nr = cr+max(-cap, min(cap, ((ar-cr)*strength+2)//4))
        nb = cb+max(-cap, min(cap, ((ab-cb)*strength+2)//4))
        ng = y-(77*nr+29*nb+128)//256
        trial = (ng+nr, ng, ng+nb)
        if all(0 <= ch <= 255 for ch in trial):
            result = trial
            status = "changed" if result != old else "same"
        else:
            status = "gamut_fallback"
    assert (77*result[0]+150*result[1]+29*result[2]+128)//256 == y
    rgb = (result[0] << 16) | (result[1] << 8) | result[2]
    return (meta << 27) | (flags << 24) | rgb, status


def make_vectors(output, count):
    rng = random.Random(20261031)
    vp, ep = output/'core_vectors.hex', output/'core_expected.hex'
    coverage = {}
    with vp.open('w', encoding='ascii') as vf, ep.open('w', encoding='ascii') as ef:
        for i in range(count):
            mode = i % 8
            meta = (rng.randrange(1 << 20) & ~(7 << 12)) | (mode << 12)
            # Full gamut plus near-channel-limit stress, correlated noise,
            # exact neighbor thresholds, blank/protect/context rejection.
            if i % 5 == 0:
                rgb = tuple(rng.choice((0, 1, 2, 253, 254, 255)) for _ in range(3))
            else:
                rgb = tuple(rng.randrange(256) for _ in range(3))
            de = int(i % 31 != 0)
            protected = int(i % 23 == 0)
            words = []
            for j in range(9):
                neighbor = tuple(max(0, min(255, ch+rng.randrange(-24, 25))) for ch in rgb)
                nd = int(i % 37 != 0 or j == 4)
                np = int(i % 29 == 0 and j != 4)
                nm = meta ^ (1 << 2) if i % 41 == 0 and j != 4 else meta
                words.append(token(neighbor, nm, nd, np))
            words[4] = token(rgb, meta, de, protected, i % 2, (i//2) % 2)
            # Every ninth directed case has perfectly uniform input; any
            # neutral/color bias would then show up as a numeric mismatch.
            if i % 9 == 0:
                words = [words[4]]*9
            expected, status = reference(words)
            coverage[status] = coverage.get(status, 0)+1
            vf.write(f'{sum(n << (j*50) for j, n in enumerate(words)):0113x}\n')
            ef.write(f'{expected:012x}\n')
    return vp, ep, coverage


def run(command, log, cwd, timeout):
    result = subprocess.run([str(s) for s in command], cwd=cwd, text=True,
                            errors='replace', stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout)
    log.write_text(result.stdout, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(f'Failed ({result.returncode}), see {log}:\n{result.stdout[-3000:]}')
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path)
    parser.add_argument('--count', type=int, default=120000)
    parser.add_argument('--timeout', type=int, default=1800)
    parser.add_argument('--core-only', action='store_true')
    parser.add_argument('--iverilog-bin', type=Path,
                        default=Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin'))
    args = parser.parse_args()
    root = args.root.resolve()
    output = (args.output or root.parent/'_build'/root.name/'c3-chroma-denoise-20261031'/'validation').resolve()
    output.mkdir(parents=True, exist_ok=True)
    summary = {'pass': False, 'scope': 'RTL core + synchronous-RAM streaming simulation',
               'board_validation': 'not_run', 'programming': 'not_run',
               'ram_model': 'Explicit NOREG synchronous read; no memory initialization; collision assertion',
               'core_vectors': args.count, 'coverage': {}}
    dut = root/'user_source/hdl_source/chroma_denoise_stream.v'
    compiler, runtime = args.iverilog_bin/'iverilog.exe', args.iverilog_bin/'vvp.exe'
    tests = root/'tools/tests'
    summary['source_sha256'] = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in (dut, tests/'tb_chroma_core.v', tests/'tb_chroma_stream.v', tests/'chroma_eram_model.v')}
    try:
        vp, ep, summary['coverage'] = make_vectors(output, args.count)
        core = output/'chroma_core.vvp'
        run([compiler, '-g2012', '-Wall', '-s', 'tb_chroma_core', '-o', core,
             tests/'tb_chroma_core.v', dut], output/'core_compile.log', root, 60)
        result = run([runtime, core, f'+vectors={vp.as_posix()}', f'+expected={ep.as_posix()}',
                      f'+count={args.count}'], output/'core_simulation.log', root, args.timeout)
        print(result, end='', flush=True)
        assert 'PASS chroma_core:' in result
        if not args.core_only:
            stream = output/'chroma_stream.vvp'
            run([compiler, '-g2012', '-Wall', '-s', 'tb_chroma_stream', '-o', stream,
                 tests/'tb_chroma_stream.v', tests/'chroma_eram_model.v', dut],
                output/'stream_compile.log', root, 60)
            result = run([runtime, stream], output/'stream_simulation.log', root, args.timeout)
            print(result, end='', flush=True)
            assert all(f'PASS chroma_stream frame D{d}:' in result for d in range(4))
            summary.update(frames=4, active_pixels=4*1280*720,
                           raster_clocks=4*1650*750, sample_latency=1658,
                           frame_pixel_count=921600, per_pixel_y8_mismatches=0,
                           protected_or_D0_rgb_mismatches=0, control_meta_mismatches=0)
        summary['pass'] = True
    except (AssertionError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        summary['error'] = str(error)
        print(f'FAIL chroma_denoise: {error}', flush=True)
    finally:
        (output/'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f'Summary: {output / "summary.json"}', flush=True)
    return 0 if summary['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
