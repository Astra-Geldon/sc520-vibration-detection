"""Offline C3 chroma-denoise study; does not build RTL or access a camera.

Run from any directory. Outputs stay under _build by default. The input is a
saved HDMI JPEG, so previews demonstrate an image-domain method, not a board
implementation or a measurement of temporal sensor noise.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

import cv2
import numpy as np


PARAMS = {
    'D1': dict(y_threshold=8, chroma_threshold=12, mix_numerator=1, cap=2),
    'D2': dict(y_threshold=12, chroma_threshold=16, mix_numerator=2, cap=4),
    'D3': dict(y_threshold=16, chroma_threshold=24, mix_numerator=3, cap=6),
}


def components(rgb):
    q = rgb.astype(np.int32)
    r, g, b = (q[..., i] for i in range(3))
    return (77*r + 150*g + 29*b + 128) >> 8, r-g, b-g


def reconstruct(rgb, dr, db):
    y, _, _ = components(rgb)
    k = (77*dr + 29*db + 128) >> 8
    g = y-k
    trial = np.stack((g+dr, g, g+db), axis=-1)
    legal = np.all((trial >= 0) & (trial <= 255), axis=-1)
    result = np.where(legal[..., None], trial, rgb).astype(np.uint8)
    return result, ~legal


def conservative_luma(rgb, protected, threshold=12):
    """Exploratory second step: symmetric integer flux, no mean darkening.

    Every edge transfers equal/opposite luma. Four-edge per-pixel gamut
    budgets avoid RGB clipping without destroying that conservation law.
    It can smooth real low-contrast texture, so this is not a selected
    production candidate or a claim to recover detail.
    """
    y = components(rgb)[0]
    q = rgb.astype(np.int32)
    up, down = (255-q.max(axis=-1))//4, q.min(axis=-1)//4
    delta = np.zeros_like(y)
    for a, b in ((np.s_[:, :-1], np.s_[:, 1:]), (np.s_[:-1, :], np.s_[1:, :])):
        diff = y[b]-y[a]
        allowed = ~protected[a] & ~protected[b] & (np.abs(diff) <= threshold)
        magnitude = (np.abs(diff)+4) >> 3
        budget = np.where(diff >= 0, np.minimum(up[a], down[b]), np.minimum(down[a], up[b]))
        flux = np.where(allowed, np.sign(diff)*np.minimum(magnitude, budget), 0)
        delta[a] += flux
        delta[b] -= flux
    trial = q+delta[..., None]
    assert trial.min() >= 0 and trial.max() <= 255
    assert int(delta.sum()) == 0
    assert np.all(delta[protected] == 0)
    out = trial.astype(np.uint8)
    assert np.array_equal(components(out)[0], y+delta)
    return out, dict(y8_sum_delta=int(delta.sum()),
                     nonprotected_y8_sum_delta=int(delta[~protected].sum()),
                     y8_max_abs_pixel_change=int(np.abs(delta).max()),
                     modified_pixels=int(np.count_nonzero(delta)),
                     threshold=threshold, kernel='4-connected symmetric conservative diffusion')


def filter_chroma(rgb, protected, params, radius=1):
    y, dr, db = components(rgb)
    h, w = y.shape
    coeff = [1, 2, 1] if radius == 1 else [1, 4, 6, 4, 1]
    divisor_shift = 4 if radius == 1 else 8
    padding = ((radius, radius), (radius, radius))
    yp, rp, bp = [np.pad(a, padding, mode='edge') for a in (y, dr, db)]
    pp = np.pad(protected, padding, mode='edge')
    sr, sb = np.zeros_like(dr), np.zeros_like(db)
    for iy, wy in enumerate(coeff):
        for ix, wx in enumerate(coeff):
            sl = np.s_[iy:iy+h, ix:ix+w]
            ok = ((np.abs(yp[sl]-y) <= params['y_threshold']) &
                  (np.abs(rp[sl]-dr) <= params['chroma_threshold']) &
                  (np.abs(bp[sl]-db) <= params['chroma_threshold']) & ~pp[sl])
            # Reject a neighbor by replacing it with the center; denominator
            # stays a power of two and no variable divider is needed.
            sr += wy*wx*np.where(ok, rp[sl], dr)
            sb += wy*wx*np.where(ok, bp[sl], db)
    half = 1 << (divisor_shift-1)
    ar, ab = (sr+half) >> divisor_shift, (sb+half) >> divisor_shift
    # Signed arithmetic shift defines rounding for negative deltas as well.
    delta_r = np.clip(((ar-dr)*params['mix_numerator']+2) >> 2,
                      -params['cap'], params['cap'])
    delta_b = np.clip(((ab-db)*params['mix_numerator']+2) >> 2,
                      -params['cap'], params['cap'])
    result, fallback = reconstruct(rgb, dr+delta_r, db+delta_b)
    bypass = protected.copy()
    bypass[:radius, :] = True
    bypass[-radius:, :] = True
    bypass[:, :radius] = True
    bypass[:, -radius:] = True
    result[bypass] = rgb[bypass]
    return result, dict(gamut_fallback_pixels=int(np.count_nonzero(fallback & ~bypass)),
                        bypass_pixels=int(np.count_nonzero(bypass)))


def math_checks():
    # Exhaust every original RGB: no-op reconstruction must be bit exact.
    gb = np.indices((256, 256), dtype=np.int32)
    checked = 0
    for r in range(256):
        rgb = np.stack((np.full((256, 256), r), gb[0], gb[1]), axis=-1).astype(np.uint8)
        _, dr, db = components(rgb)
        out, fallback = reconstruct(rgb, dr, db)
        assert np.array_equal(rgb, out) and not fallback.any()
        checked += rgb.shape[0]*rgb.shape[1]
    rng = np.random.default_rng(20261031)
    rgb = rng.integers(0, 256, (1_000_000, 3), dtype=np.uint8)
    dr = rng.integers(-255, 256, 1_000_000, dtype=np.int32)
    db = rng.integers(-255, 256, 1_000_000, dtype=np.int32)
    out, fallback = reconstruct(rgb, dr, db)
    assert np.array_equal(components(rgb)[0], components(out)[0])
    assert np.array_equal(out[fallback], rgb[fallback])
    for color in ((0, 0, 0), (255, 255, 255), (20, 80, 140), (170, 90, 45), (255, 0, 0)):
        block = np.empty((24, 32, 3), dtype=np.uint8)
        block[...] = color
        for p in PARAMS.values():
            out, _ = filter_chroma(block, np.zeros(block.shape[:2], dtype=bool), p)
            assert np.array_equal(out, block)
    # Full-range colored stress with random protected pixels checks the
    # paired gamut budget and exact global/nonprotected luma conservation.
    stress = rng.integers(0, 256, (256, 320, 3), dtype=np.uint8)
    protected = rng.random(stress.shape[:2]) < .15
    conservative_luma(stress, protected)
    flat = np.empty((64, 64, 3), dtype=np.uint8)
    flat[:] = (40, 90, 180)
    out, _ = conservative_luma(flat, np.zeros(flat.shape[:2], dtype=bool))
    assert np.array_equal(flat, out)
    return dict(noop_all_rgb_cases=checked, noop_rgb_mismatches=0,
                random_chroma_cases=len(rgb), random_y8_mismatches=0,
                arbitrary_chroma_fallback_cases=int(fallback.sum()),
                arbitrary_chroma_scope='Full-range stress, not expected real-image fallback rate',
                uniform_color_cases=15, uniform_color_mismatches=0,
                conservative_luma_stress_pixels=81920,
                conservative_luma_clipping_or_conservation_failures=0)


def patch_metrics(rgb, roi):
    x0, y0, x1, y1 = roi
    patch = rgb[y0:y1, x0:x1]
    ycc = cv2.cvtColor(patch, cv2.COLOR_RGB2YCrCb).astype(np.float32)
    lp9 = cv2.GaussianBlur(ycc, (9, 9), 0)
    lp31 = cv2.GaussianBlur(ycc, (31, 31), 0)
    inner = np.s_[16:-16, 16:-16]
    y8 = components(patch)[0]
    return dict(mean_y8=float(y8.mean()),
                mean_RGB=patch.mean(axis=(0, 1)).tolist(),
                std_highpass9_YCrCb=(ycc-lp9)[inner].std(axis=(0, 1)).tolist(),
                std_band9_to31_YCrCb=(lp9-lp31)[inner].std(axis=(0, 1)).tolist())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parents[1]
    base = root.parent / '_build' / root.name
    parser.add_argument('--input', type=Path,
                        default=base / 'tone-quality-analysis-20261031/samples/original3_C3.jpg')
    parser.add_argument('--output', type=Path,
                        default=base / 'brightness-preserving-denoise-study-20261031')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    raw = cv2.imread(str(args.input))
    if raw is None:
        raise RuntimeError(f'Cannot read saved sample: {args.input}')
    rgb = cv2.cvtColor(cv2.resize(raw, (1280, 720), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2RGB)
    yref = components(rgb)[0]
    # JPEG lacks the real pre-tone H1 flag. This conservative proxy is ONLY
    # for previews; production must carry the original protection flag.
    protected = rgb.max(axis=2) >= 208
    protected[:92, :240] = True  # Existing text/OSD excluded from study.
    protected[:100, 1120:] = True
    cv2.imwrite(str(args.output / 'source_C3_native.png'), cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))
    regions = {'cabinet': (180, 220, 447, 407), 'right_wall': (927, 200, 1167, 567)}
    summary = dict(scope='Offline post-C3 JPEG proxy; no RTL, camera access, or board acceptance',
                   source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                   source_image=str(args.input.resolve()),
                   source_image_sha256=hashlib.sha256(args.input.read_bytes()).hexdigest(),
                   user_policy='Keep C3 brightness; compare original C3 plus D1/D2/D3',
                   protected_mask_scope='Conservative post-C3 JPEG proxy; actual pre-tone flag unavailable',
                   math_checks=math_checks(), input_regions={k: patch_metrics(rgb, v) for k, v in regions.items()},
                   candidates={})
    previews = {'D0': rgb}
    for name, params in PARAMS.items():
        out, stats = filter_chroma(rgb, protected, params)
        yerr = components(out)[0]-yref
        assert not np.any(yerr)
        assert np.array_equal(out[protected], rgb[protected])
        ocv_yerr = (cv2.cvtColor(out, cv2.COLOR_RGB2YCrCb)[..., 0].astype(int)-
                    cv2.cvtColor(rgb, cv2.COLOR_RGB2YCrCb)[..., 0].astype(int))
        stats.update(params=params, kernel='3x3 fixed binomial /16',
                     y8_pixel_mismatches=int(np.count_nonzero(yerr)),
                     y8_mean_delta=float(yerr.mean()),
                     opencv_y_max_abs_delta=int(np.abs(ocv_yerr).max()),
                     protected_rgb_mismatches=int(np.any(out[protected] != rgb[protected], axis=-1).sum()),
                     modified_pixels=int(np.any(out != rgb, axis=-1).sum()),
                     regions={k: patch_metrics(out, v) for k, v in regions.items()})
        summary['candidates'][name] = stats
        previews[name] = out
        cv2.imwrite(str(args.output / f'C3_{name}_preview.png'), cv2.cvtColor(out, cv2.COLOR_RGB2BGR))
    # Exploratory larger kernel: same fixed-Y math, not part of first hardware proposal.
    out5, stats5 = filter_chroma(rgb, protected, PARAMS['D3'], radius=2)
    assert np.array_equal(components(out5)[0], yref)
    stats5.update(kernel='5x5 binomial /256; exploratory', y8_pixel_mismatches=0,
                  regions={k: patch_metrics(out5, v) for k, v in regions.items()})
    summary['exploratory_5x5_D3'] = stats5
    lout, lstats = conservative_luma(previews['D3'], protected)
    lstats.update(scope='Optional later luma stage; real low-contrast texture may also be smoothed',
                  regions={k: patch_metrics(lout, v) for k, v in regions.items()})
    summary['exploratory_D3_conservative_luma'] = lstats
    cv2.imwrite(str(args.output / 'C3_D3_optional_luma_preview.png'), cv2.cvtColor(lout, cv2.COLOR_RGB2BGR))
    # Label a cabinet crop at 2x, using the same scaling for every candidate.
    tiles = []
    for name, im in previews.items():
        tile = cv2.cvtColor(im[230:430, 180:480], cv2.COLOR_RGB2BGR)
        tile = cv2.resize(tile, (600, 400), interpolation=cv2.INTER_NEAREST)
        tile = cv2.copyMakeBorder(tile, 42, 0, 0, 0, cv2.BORDER_CONSTANT, value=(30, 30, 30))
        label = 'Original C3' if name == 'D0' else f'C3 + {name}'
        cv2.putText(tile, label+' (offline)', (12, 28), cv2.FONT_HERSHEY_SIMPLEX, .7, (240, 240, 240), 1)
        tiles.append(tile)
    comparison = np.vstack((np.hstack(tiles[:2]), np.hstack(tiles[2:])))
    cv2.imwrite(str(args.output / 'cabinet_comparison.png'), comparison)
    (args.output / 'study_summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    for name, row in summary['candidates'].items():
        print(name, 'Y8 mismatches:', row['y8_pixel_mismatches'],
              'gamut fallback:', row['gamut_fallback_pixels'])
        for region, met in row['regions'].items():
            ref = np.array(summary['input_regions'][region]['std_highpass9_YCrCb'])
            ratio = np.array(met['std_highpass9_YCrCb'])/ref
            print(' ', region, 'Y/Cr/Cb highpass ratio:', np.round(ratio, 4))
    print('Summary:', args.output / 'study_summary.json')


if __name__ == '__main__':
    main()
