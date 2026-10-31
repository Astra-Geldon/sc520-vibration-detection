"""Controlled C3/D response study. No camera, board access, or RTL edits.

Reads the actual C3 LUT, then measures deterministic synthetic signals.
These are algorithm responses, not sensor-noise measurements or predictions
that an unimplemented candidate will improve a real scene.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re

import cv2
import numpy as np

from study_brightness_preserving_denoise import components, filter_chroma, reconstruct, PARAMS


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=root.parent / '_build' /
                        root.name / 'deep-image-audit-20261031' / 'tone-response')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    source = root / 'user_source/hdl_source/highlight_tone.v'
    entries = re.findall(r"8'd(\d+): f_boost_pair = \{18'd(\d+), 18'd(\d+)\}",
                         source.read_text(encoding='utf-8'))
    boost = np.zeros(256, dtype=np.int64)
    assert len(entries) == 208
    for peak, strong, _ in entries:
        m, v = int(peak), int(strong)
        assert v == (208-m)*256 + 2*(208-m)**2
        boost[m] = v

    def tone(rgb):
        q = rgb.astype(np.int64)
        out = q + ((q*boost[q.max(axis=-1)][..., None] + 32768) >> 16)
        assert out.min() >= 0 and out.max() <= 255
        return out.astype(np.uint8)

    def summary(rgb, border=8):
        y, dr, db = components(rgb[border:-border, border:-border])
        return {'mean_Y8': float(y.mean()), 'std_Y8': float(y.std()),
                'std_R_minus_G': float(dr.std()), 'std_B_minus_G': float(db.std())}

    rng = np.random.default_rng(20261031)
    shape = (256, 512)
    result = {'scope': 'Controlled synthetic algorithm response; not board SNR',
              'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'lut_rows_verified': len(entries), 'neutral_levels': {},
              'flat_RGB_noise': {}, 'broad_chroma': {}, 'texture': {},
              'constant_Y8_chroma_noise': {}}
    for level in (16, 32, 50, 80, 100, 128, 150, 160, 180, 208):
        q = np.full((1, 1, 3), level, dtype=np.uint8)
        result['neutral_levels'][level] = int(tone(q)[0, 0, 0])

    for level in (50, 80, 128, 160):
        q = np.clip(level+rng.normal(0, 2, (*shape, 3)), 0, 255).round().astype(np.uint8)
        c3 = tone(q)
        d3, _ = filter_chroma(c3, np.zeros(shape, dtype=bool), PARAMS['D3'])
        assert np.array_equal(components(c3)[0], components(d3)[0])
        result['flat_RGB_noise'][level] = {'input': summary(q), 'C3': summary(c3),
                                         'C3_D3': summary(d3)}

    # The maxRGB-based control path can convert a color-only perturbation
    # into brightness variation. Later fixed-Y D must preserve that artifact.
    for level in (80, 128, 160):
        neutral = np.full((*shape, 3), level, dtype=np.uint8)
        dr = rng.integers(-4, 5, shape)
        db = rng.integers(-4, 5, shape)
        q, fallback = reconstruct(neutral, dr, db)
        assert not fallback.any() and np.all(components(q)[0] == level)
        c3 = tone(q)
        d3, _ = filter_chroma(c3, np.zeros(shape, dtype=bool), PARAMS['D3'])
        result['constant_Y8_chroma_noise'][level] = {
            'input': summary(q), 'C3': summary(c3), 'C3_D3': summary(d3),
            'C3_output_Y8_range': [int(components(c3)[0].min()), int(components(c3)[0].max())]}
    example = np.array([[[128, 128, 128], [131, 127, 127]]], dtype=np.uint8)
    result['equal_luma_example'] = {'input_RGB': example[0].tolist(),
                                  'input_Y8': components(example)[0][0].tolist(),
                                  'output_RGB': tone(example)[0].tolist(),
                                  'output_Y8': components(tone(example))[0][0].tolist()}

    # Known 16px luminance structure at different DC levels. A useful
    # alternative must retain structure without simply sharpening noise.
    x = np.arange(shape[1])[None, :]
    for level in (80, 128, 160):
        stripe = np.broadcast_to(level+np.rint(8*np.sin(2*np.pi*x/16)), shape)
        q = np.repeat(stripe[..., None], 3, axis=2).astype(np.uint8)
        c3 = tone(q)
        d3, _ = filter_chroma(c3, np.zeros(shape, dtype=bool), PARAMS['D3'])
        assert np.array_equal(c3, d3)
        contrast_in = float(components(q)[0].std())
        contrast_out = float(components(c3)[0].std())
        result['texture'][level] = {'input_std_Y8': contrast_in,
                                   'C3_std_Y8': contrast_out,
                                   'contrast_retained': contrast_out/contrast_in,
                                   'D3_recovery': 0.0}

    # Pure broad color variation: hold the luma component nearly constant.
    # This is a scale-response example, not a claim that a wall's colors
    # are noise. Two Y8 quantization values may occur in this construction.
    for period in (16, 32, 64):
        dr = np.broadcast_to(np.rint(8*np.sin(2*np.pi*x/period)), shape).astype(np.int32)
        db = -dr
        g = 160 - ((77*dr+29*db+128) >> 8)
        q = np.stack((g+dr, g, g+db), axis=-1).astype(np.uint8)
        out, _ = filter_chroma(q, np.zeros(shape, dtype=bool), PARAMS['D3'])
        result['broad_chroma'][period] = {
            'ideal_all_gates_open_attenuation_fraction': float(.75*np.sin(np.pi/period)**2),
            'input': summary(q), 'D3': summary(out),
            'modified_fraction': float(np.any(q[8:-8,8:-8] != out[8:-8,8:-8], axis=-1).mean())}

    # A spatially constant gain can preserve texture contrast that a
    # pixel-dependent tone curve compresses. This diagnostic uses a known
    # synthetic DC base (an oracle), not a deployable base estimator.
    level = 160
    stripe = np.broadcast_to(level+np.rint(8*np.sin(2*np.pi*x/16)), shape)
    q = np.repeat(stripe[..., None], 3, axis=2).astype(np.uint8)
    c3 = tone(q)
    gain = 1+int(boost[level])/65536
    local = np.rint(q.astype(float)*gain).astype(np.int32)
    offset = float(c3.mean()-local.mean())
    local = np.clip(np.rint(local+offset), 0, 255).astype(np.uint8)
    result['oracle_base_diagnostic'] = {
        'scope': 'Known synthetic base only; no deployable estimator or noise model',
        'input': summary(q), 'C3': summary(c3), 'constant_base_gain': summary(local),
        'mean_alignment_offset': offset,
        'warning': 'A real gain field must protect highlights, suppress noise and avoid halos'}

    # Curve and contrast response, exported as a standalone scientific plot.
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    levels = np.arange(256)
    neutral = tone(np.repeat(levels[:,None,None],3,axis=2).astype(np.uint8))[:,0,0]
    fig, axes = plt.subplots(1, 2, figsize=(10, 3.7), constrained_layout=True)
    axes[0].plot(levels, levels, '--', label='Identity')
    axes[0].plot(levels, neutral, label='Actual C3 LUT')
    axes[0].set(xlabel='Input neutral RGB code', ylabel='Output code', xlim=(0,255), ylim=(0,255))
    axes[0].legend(); axes[0].grid(alpha=.25)
    centers = list(result['texture'])
    axes[1].bar([str(i) for i in centers],
                [result['texture'][i]['contrast_retained'] for i in centers])
    axes[1].set(xlabel='Input mean (8-code sinusoidal detail)',
                ylabel='Output / input luminance contrast', ylim=(0,1.25))
    axes[1].grid(axis='y', alpha=.25)
    fig.savefig(args.output/'c3_detail_response.png', dpi=160)
    plt.close(fig)
    (args.output/'summary.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'texture':result['texture'], 'broad_chroma':result['broad_chroma'],
                      'constant_Y8_chroma_noise':result['constant_Y8_chroma_noise'],
                      'equal_luma_example':result['equal_luma_example'],
                      'oracle_base_diagnostic':result['oracle_base_diagnostic'],
                      'output':str(args.output)}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
