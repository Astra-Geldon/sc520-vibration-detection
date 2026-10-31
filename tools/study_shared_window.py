"""Offline alternative: denoise and gain base share ONE raw-pixel window.

This changes the algorithm relative to sequential box_base. No RTL, synthesis,
camera or board use. Sigma is supplied by synthetic tests, not estimated.
"""
from pathlib import Path
import hashlib
import json

import cv2
import numpy as np

from study_zero_dsp_candidates import Model, ARTIFACT, components, prefilter, scenes, y8


def apply_compact_base(rgb, model, noise=4, size=5):
    """Same sequential S structure, smaller symmetric base/guard support."""
    q = prefilter(rgb, noise, symmetric_y=True, symmetric_color=True).astype(np.int64)
    peak = q.max(axis=-1)
    weights = np.array([1]+[2]*(size-2)+[1], np.float32)
    denominator = int(weights.sum())**2
    summed = cv2.sepFilter2D((peak*16).astype(np.float32), -1, weights, weights,
                            borderType=cv2.BORDER_REPLICATE)
    base = (summed.astype(np.int32)+denominator//2)//denominator
    protected = rgb.max(axis=-1) >= 208
    edge = protected.astype(np.uint8)
    guide = y8(q)
    threshold = max(16, int(noise*4))
    for axis in (0,1):
        a = [slice(None),slice(None)]; b = a.copy()
        a[axis] = slice(1,None); b[axis] = slice(None,-1)
        a,b = tuple(a),tuple(b)
        hit = (np.abs(peak[a]-peak[b]) >= threshold) | (np.abs(guide[a]-guide[b]) >= threshold)
        edge[a] |= hit; edge[b] |= hit
    guard = cv2.dilate(edge, np.ones((size,size),np.uint8)) != 0
    base = np.where(guard, peak*16, base)
    ix,frac = base >> 4, base & 15
    boost = model.boost[ix]+((model.boost[ix+1]-model.boost[ix])*frac+8)//16
    boost = np.minimum(boost,model.cap[peak])
    trial = q+((q*boost[...,None]+32768) >> 16)
    assert trial.min() >= 0 and trial.max() <= 255
    return np.where(protected[...,None],rgb,trial).astype(np.uint8)


def apply_shared(rgb, model, noise=4, size=3, base_gain=True):
    q = rgb.astype(np.int64)
    y = y8(rgb).astype(np.int64)
    dr, db = q[..., 0]-q[..., 1], q[..., 2]-q[..., 1]
    peak = q.max(axis=-1)
    protected = peak >= 208
    radius = size//2
    weights = (1, 2, 1) if size == 3 else (1, 4, 6, 4, 1)
    yt = min(24, max(6, int(noise*3)))
    ct = min(48, max(12, int(noise*6)))
    # Y8 is intentionally stored, not Q4. This keeps the line token small.
    values = np.stack((y, dr, db, peak), axis=-1)
    padded = np.pad(values, ((radius, radius), (radius, radius), (0, 0)), mode='edge')
    acc = np.zeros_like(values)
    for iy, wy in enumerate(weights):
        for ix, wx in enumerate(weights):
            n = padded[iy:iy+q.shape[0], ix:ix+q.shape[1]]
            valid = (np.abs(n[..., 0]-y) <= yt)
            valid &= (np.abs(n[..., 1]-dr) <= ct) & (np.abs(n[..., 2]-db) <= ct)
            valid &= (n[..., 3] < 208) & ~protected
            acc += (wy*wx)*np.where(valid[..., None], n, values)
    denominator = sum(weights)**2
    # Q4 exists only AFTER the shared window, in arithmetic pipeline registers.
    avgq = (acc*16+denominator//2)//denominator
    yf = (y*16+3*avgq[..., 0]+2) >> 2
    cf = avgq[..., 1:3]
    gf = yf-((77*cf[..., 0]+29*cf[..., 1]+128) >> 8)
    candidate = (np.stack((gf+cf[..., 0], gf, gf+cf[..., 1]), axis=-1)+8) >> 4
    legal = np.all((candidate >= 0) & (candidate <= 255), axis=-1)
    clean = np.where((legal & ~protected)[..., None], candidate, q)
    clean_peak = clean.max(axis=-1)
    base = avgq[..., 3] if base_gain else clean_peak*16
    ix, frac = base >> 4, base & 15
    boost = model.boost[ix]+((model.boost[ix+1]-model.boost[ix])*frac+8)//16
    boost = np.minimum(boost, model.cap[clean_peak])
    trial = clean+((clean*boost[..., None]+32768) >> 16)
    assert trial.min() >= 0 and trial.max() <= 255
    return np.where(protected[..., None], q, trial).astype(np.uint8)


def main():
    output = ARTIFACT/'zero-dsp-research-20261031/shared-window'
    output.mkdir(parents=True, exist_ok=True)
    model = Model()
    rng = np.random.default_rng(20261031)
    report = {'scope': 'Synthetic algorithm research, not board quality or mapped resources',
              'source_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'architecture_DSP_addition': 0, 'cases': [], 'uniform_checks': 0,
              'noise_scope': 'Known synthetic RGB sigma; current900 profile not calibrated'}
    paths = [('C3', None), ('box_base', None), ('shared3_pre', (3, False)),
             ('shared3_base', (3, True)), ('shared5_base', (5, True)),
             ('compact_base3', 3), ('compact_base5', 5)]
    def runner(kind, settings, noise):
        if settings is None:
            return lambda im: model.apply(im,kind,noise)
        if isinstance(settings,int):
            return lambda im: apply_compact_base(im,model,noise,settings)
        return lambda im: apply_shared(im,model,noise,*settings)
    tiles = []
    for name, clean in scenes().items():
        mask = clean.max(axis=-1) < 208
        mask[:10] = mask[-10:] = False
        mask[:, :10] = mask[:, -10:] = False
        row = []
        for noise in (2, 4, 8):
            noisy = np.clip(clean.astype(float)+rng.normal(0, noise, clean.shape), 0, 255).round().astype(np.uint8)
            old = model.apply(noisy, 'C3')
            for kind, settings in paths:
                run = runner(kind,settings,noise)
                out, noiseless = run(noisy), run(clean)
                diff = components(out)-components(noiseless)
                rotated = np.rot90(run(np.rot90(noisy).copy()), -1)
                report['cases'].append({
                    'scene': name, 'sigma_RGB': noise, 'candidate': kind,
                    'noise_RMSE_Y_Dr_Db': np.sqrt(np.mean(diff[mask]**2, axis=0)).tolist(),
                    'noiseless_std_Y8': float(y8(noiseless)[mask].std()),
                    'mean_Y_delta_percent': 100*(float(y8(out)[mask].mean())/float(y8(old)[mask].mean())-1),
                    'rotation90_max_RGB': int(np.abs(out.astype(int)-rotated.astype(int))[10:-10,10:-10].max()),
                    'protected_mismatch': int(np.any(out[noisy.max(axis=-1)>=208] != noisy[noisy.max(axis=-1)>=208], axis=-1).sum())})
                if noise == 4 and name in ('known_texture', 'skin_shading', 'color_edges_highlight'):
                    tile = cv2.cvtColor(out, cv2.COLOR_RGB2BGR)
                    tile = cv2.copyMakeBorder(tile, 28, 0, 0, 0, cv2.BORDER_CONSTANT, value=(25,25,25))
                    cv2.putText(tile, kind, (8,20), cv2.FONT_HERSHEY_SIMPLEX, .49, (245,245,245), 1)
                    row.append(tile)
        if row:
            tiles.append(np.hstack(row))
    for size in (3, 5):
        for color in ((0,0,0),(1,1,1),(40,40,40),(128,128,128),(207,207,207),
                      (208,208,208),(118,90,72),(20,100,40),(255,255,255)):
            im = np.broadcast_to(np.array(color, np.uint8), (24,24,3)).copy()
            assert np.array_equal(apply_shared(im,model,4,size),model.apply(im,'C3'))
            report['uniform_checks'] += 1
            assert np.array_equal(apply_compact_base(im,model,4,size),model.apply(im,'C3'))
            report['uniform_checks'] += 1
    report['compact9_equivalence_checks'] = 0
    for noise in (2,4,8):
        im = rng.integers(0,256,(48,64,3),dtype=np.uint8)
        assert np.array_equal(apply_compact_base(im,model,noise,9), model.apply(im,'box_base',noise))
        report['compact9_equivalence_checks'] += 1
    boundaries = []
    for strength in (8,16,32):
        im = np.full((160,256,3),125,np.uint8)
        im[:,:128,0] += strength//2
        im[:,128:,0] -= strength//2
        for kind, settings in paths:
            out = runner(kind,settings,4)(im)
            dr = components(out)[80,:,1]
            low, high = float(dr[180:220].mean()), float(dr[36:76].mean())
            band = (dr > low+.1*(high-low)) & (dr < low+.9*(high-low))
            boundaries.append({'strength':strength,'candidate':kind,'edge_width_10_90':int(band[100:156].sum())})
    report['boundaries'] = boundaries
    (output/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    cv2.imwrite(str(output/'comparison.png'),np.vstack(tiles))
    print(json.dumps({'texture_sigma4':[x for x in report['cases'] if x['scene']=='known_texture' and x['sigma_RGB']==4],
                      'max_brightness_shift':[{'candidate':kind,'max_abs_percent':max(abs(x['mean_Y_delta_percent']) for x in report['cases'] if x['candidate']==kind)} for kind,_ in paths],
                      'boundaries':boundaries,'uniform_checks':report['uniform_checks']},ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
