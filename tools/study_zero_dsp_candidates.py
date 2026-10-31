"""Offline integer candidates under a zero-additional-DSP architecture.

No production RTL, synthesis, camera or board access. Synthetic ground truth
tests algorithm tradeoffs, not measured SC520 SNR. Saved HDMI JPEG trials are
postprocessed proxies only. Physical resource counts remain unverified.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = ROOT.parent / '_build' / ROOT.name
TRI15 = np.array([1,2,3,4,5,6,7,8,7,6,5,4,3,2,1], dtype=np.int32)


def y8(rgb):
    r, g, b = np.moveaxis(rgb.astype(np.int32), -1, 0)
    return (77*r+150*g+29*b+128) >> 8


def horizontal(values, guide, protected, weights, yt, ct=None):
    """Power-of-two denominator, rejected taps replaced with center.

    Multiplication here models CONSTANT small integer weights, implemented
    as shifts/adds in a future RTL. No variable division or weight product.
    values and guide have four fractional bits.
    """
    radius = len(weights)//2
    assert int(weights.sum()) in (4, 16, 64)
    padded = np.pad(values, ((0,0),(radius,radius),(0,0)), mode='edge')
    gp = np.pad(guide, ((0,0),(radius,radius)), mode='edge')
    pp = np.pad(protected, ((0,0),(radius,radius)), mode='edge')
    acc = np.zeros_like(values)
    for i, weight in enumerate(weights):
        neighbor = padded[:, i:i+values.shape[1]]
        valid = (np.abs(gp[:,i:i+guide.shape[1]]-guide) <= yt*16)
        valid &= ~pp[:,i:i+guide.shape[1]] & ~protected
        if ct is not None:
            valid &= np.max(np.abs(neighbor-values), axis=-1) <= ct*16
        acc += int(weight)*np.where(valid[...,None], neighbor, values)
    shift = int(weights.sum()).bit_length()-1
    return (acc+(1 << (shift-1))) >> shift


def vertical_iir(values, guide, protected, yt, shift, ct=None):
    """One prior ROW of same frame, no temporal/frame history.

    v = previous + (current-previous)/2**shift in flat regions.
    At guide/color edges restart from current. This causal form needs
    explicit directionality/streak tests; it is not a symmetric 2D filter.
    """
    out = np.empty_like(values)
    out[0] = values[0]
    for row in range(1, values.shape[0]):
        valid = (np.abs(guide[row]-guide[row-1]) <= yt*16)
        valid &= ~protected[row] & ~protected[row-1]
        if ct is not None:
            valid &= np.max(np.abs(values[row]-out[row-1]), axis=-1) <= ct*16
        if shift == 0:
            # Weak vertical smoothing: 3/4 current + 1/4 previous.
            trial = (3*values[row]+out[row-1]+2) >> 2
        else:
            trial = out[row-1]+((values[row]-out[row-1]+(1<<(shift-1))) >> shift)
        out[row] = np.where(valid[...,None], trial, values[row])
    return out


def horizontal_iir(values, guide, protected, yt, shift, ct=None):
    # Transpose to reuse the exact same one-dimensional recurrence. An RTL
    # horizontal recurrence has a one-pixel feedback timing requirement.
    return np.transpose(vertical_iir(np.transpose(values,(1,0,2)),guide.T,
                                    protected.T,yt,shift,ct),(1,0,2))


def vertical_fir3(values, guide, protected, yt):
    padded = np.pad(values, ((1,1),(0,0),(0,0)), mode='edge')
    gp = np.pad(guide, ((1,1),(0,0)), mode='edge')
    pp = np.pad(protected, ((1,1),(0,0)), mode='edge')
    acc = np.zeros_like(values)
    for i, weight in enumerate((1,2,1)):
        valid = np.abs(gp[i:i+guide.shape[0]]-guide) <= yt*16
        valid &= ~pp[i:i+guide.shape[0]] & ~protected
        acc += weight*np.where(valid[...,None],padded[i:i+values.shape[0]],values)
    return (acc+2) >> 2


def prefilter(rgb, noise, symmetric_y=False, iir_color=False, symmetric_color=False):
    q = rgb.astype(np.int32)
    r, g, b = np.moveaxis(q, -1, 0)
    yq = (77*r+150*g+29*b+8) >> 4
    color = np.stack(((r-g)*16, (b-g)*16), axis=-1)
    protected = q.max(axis=-1) >= 208
    yt = min(24, max(6, int(noise*3)))
    ct = min(48, max(12, int(noise*6)))
    yf = horizontal(yq[...,None], yq, protected, np.array([1,2,1]), yt)
    if symmetric_y:
        yf = vertical_fir3(yf, yq, protected, yt)
        yf = ((yq[...,None]+3*yf+2) >> 2)[...,0]
    else:
        yf = (3*yq[...,None]+yf+2) >> 2
        yf = vertical_iir(yf, yq, protected, yt, 0)[...,0]
    if symmetric_color:
        cf = horizontal(color,yq,protected,np.array([1,2,1]),yt,ct)
        # Separable Y-guided color filtering still needs a chroma edge
        # guard vertically; keep isolated real color edges when >CT.
        padded=np.pad(cf,((1,1),(0,0),(0,0)),mode='edge')
        gp=np.pad(yq,((1,1),(0,0)),mode='edge')
        pp=np.pad(protected,((1,1),(0,0)),mode='edge')
        acc=np.zeros_like(cf)
        for i,weight in enumerate((1,2,1)):
            neighbor=padded[i:i+cf.shape[0]]
            valid=(np.abs(gp[i:i+cf.shape[0]]-yq)<=yt*16)
            valid &= ~pp[i:i+cf.shape[0]] & ~protected
            valid &= np.max(np.abs(neighbor-cf),axis=-1)<=ct*16
            acc += weight*np.where(valid[...,None],neighbor,cf)
        cf=(acc+2)>>2
    else:
        cf = (horizontal_iir(color,yq,protected,yt,2,ct) if iir_color else
              horizontal(color,yq,protected,TRI15,yt,ct))
        cf = vertical_iir(cf,yq,protected,yt,2,ct)
    gf = yf-((77*cf[...,0]+29*cf[...,1]+128) >> 8)
    trial = np.stack((gf+cf[...,0], gf, gf+cf[...,1]), axis=-1)
    trial = (trial+8) >> 4
    legal = np.all((trial >= 0) & (trial <= 255), axis=-1)
    return np.where((legal & ~protected)[...,None], trial, q).astype(np.uint8)


class Model:
    def __init__(self):
        source = ROOT/'user_source/hdl_source/highlight_tone.v'
        self.source_sha256 = hashlib.sha256(source.read_bytes()).hexdigest()
        entries = re.findall(r"8'd(\d+): f_boost_pair = \{18'd(\d+), 18'd(\d+)\}",
                             source.read_text(encoding='utf-8'))
        assert len(entries) == 208
        self.boost = np.zeros(257, dtype=np.int64)
        for m, v, _ in entries:
            self.boost[int(m)] = int(v)
        # Cap derived offline; no pixel divider. Same 18-bit multiplier input.
        self.cap = np.array([139776 if m == 0 else
                             min(139776, max(0, ((208-m)*65536)//m))
                             for m in range(256)], dtype=np.int64)

    def apply(self, rgb, kind, noise=3):
        protected = rgb.max(axis=-1) >= 208
        if kind == 'C3':
            clean = rgb
        else:
            clean = prefilter(rgb,noise,symmetric_y=(kind in ('base_gain_y3','low_cost_iir','box_base')),
                              iir_color=(kind=='low_cost_iir'),symmetric_color=(kind=='box_base'))
        q = clean.astype(np.int64)
        peak = q.max(axis=-1)
        if kind not in ('base_gain','base_gain_y3','low_cost_iir','box_base'):
            boost = self.boost[peak]
        else:
            guide = y8(clean)*16
            if kind=='box_base':
                # Symmetric 9tap [1,2,2,2,2,2,2,2,1]/16. Implementable
                # with a rolling8 sum plus the two endpoints, not 81
                # variable weights. Float32 is EXACT for these small
                # integer sums (<2**24); this is an integer-kernel model.
                weights=np.array([1,2,2,2,2,2,2,2,1],dtype=np.float32)
                summed=cv2.sepFilter2D((peak*16).astype(np.float32),-1,weights,weights,
                                       borderType=cv2.BORDER_REPLICATE)
                base=(summed.astype(np.int32)+128)>>8
                edge=np.zeros(peak.shape,dtype=np.uint8)
                threshold=max(16,int(noise*4))
                for axis in (0,1):
                    a=[slice(None),slice(None)]; b=a.copy()
                    a[axis]=slice(1,None); b[axis]=slice(None,-1)
                    a,b=tuple(a),tuple(b)
                    hit=(np.abs(peak[a]-peak[b])>=threshold) | (np.abs(guide[a]-guide[b])>=threshold*16)
                    edge[a] |= hit; edge[b] |= hit
                edge |= protected
                # Exclude the COMPLETE base support near detected edges.
                near_edge=cv2.dilate(edge,np.ones((9,9),np.uint8))!=0
                base=np.where(near_edge,peak*16,base)
            else:
                base_values=(peak*16)[...,None].astype(np.int32)
                base = (horizontal_iir(base_values,guide,protected,32,2) if kind=='low_cost_iir' else
                        horizontal(base_values,guide,protected,TRI15,32))
                base=vertical_iir(base,guide,protected,32,2)[...,0]
            base = np.clip(base, 0, 255*16)
            ix, frac = base >> 4, base & 15
            # Small 4-bit fractional interpolation may be implemented with
            # four conditional shifted adds; no extra DSP is budgeted.
            boost = self.boost[ix]+((self.boost[ix+1]-self.boost[ix])*frac+8)//16
            boost = np.minimum(boost, self.cap[peak])
        trial = q+((q*boost[...,None]+32768) >> 16)
        assert trial.min() >= 0 and trial.max() <= 255
        out = np.where(protected[...,None], rgb, trial).astype(np.uint8)
        assert np.array_equal(out[protected], rgb[protected])
        return out


def components(rgb):
    q = rgb.astype(np.float64)
    return np.stack((y8(rgb), q[...,0]-q[...,1], q[...,2]-q[...,1]), axis=-1)


def scenes():
    h, w = 192, 320
    yy, xx = np.indices((h,w))
    out = {}
    for level in (40,80,128,160):
        out[f'flat{level}'] = np.full((h,w,3), level, dtype=np.uint8)
    gray = 140+8*np.sin(2*np.pi*xx/16)+4*np.sin(2*np.pi*yy/32)
    out['known_texture'] = np.repeat(np.rint(gray)[...,None], 3, axis=-1).astype(np.uint8)
    skin = np.empty((h,w,3), dtype=np.float64)
    shade = .65+.35*xx/w
    for i,v in enumerate((118,90,72)):
        skin[...,i] = v*shade+3*np.sin(2*np.pi*xx/24)
    out['skin_shading'] = np.rint(skin).astype(np.uint8)
    chart = np.zeros((h,w,3), dtype=np.uint8)
    for i,color in enumerate(((38,40,42),(128,128,128),(180,70,40),(35,110,55),(40,80,170))):
        chart[:,i*64:(i+1)*64] = color
    chart[25:50,125:195] = (230,235,240)
    chart[100:105,20:300] = 20
    out['color_edges_highlight'] = chart
    # Static broad chroma field must not be scored as random noise. A filter
    # preserving real low-frequency color cannot generally know it is error.
    dr = np.rint(6*np.sin(2*np.pi*xx/64)).astype(np.int32)
    db = -dr
    g = 100-((77*dr+29*db+128)>>8)
    out['ambiguous_broad_color'] = np.stack((g+dr,g,g+db),axis=-1).astype(np.uint8)
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ARTIFACT/'zero-dsp-research-20261031')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    model = Model()
    rng = np.random.default_rng(20261031)
    report = {'scope':'Offline integer/synthetic study; no RTL or TD build',
              'DSP_limit':34, 'additional_DSP_architecture_budget':0,
              'physical_resource_verification':'not_run',
              'noise_parameter_scope':'Known synthetic sigma supplied as a profile; no calibrated 900-exposure estimator yet',
              'source_sha256':model.source_sha256, 'cases':[]}
    pictures = {}
    for name, clean in scenes().items():
        baseline = model.apply(clean, 'C3')
        mask = clean.max(axis=-1) < 208
        mask[:10] = mask[-10:] = False
        mask[:,:10] = mask[:,-10:] = False
        for noise in (2,4,8):
            noisy = np.clip(clean.astype(float)+rng.normal(0,noise,clean.shape),0,255).round().astype(np.uint8)
            old = model.apply(noisy,'C3')
            for kind in ('C3','pre_only','base_gain','base_gain_y3','low_cost_iir','box_base'):
                noiseless = model.apply(clean,kind,noise)
                out = old if kind == 'C3' else model.apply(noisy,kind,noise)
                diff = components(out)-components(noiseless)
                mean_y = float(y8(out)[mask].mean())
                old_mean = float(y8(old)[mask].mean())
                record = {'scene':name,'input_noise_sigma_RGB':noise,'candidate':kind,
                          'noise_RMSE_Y_Dr_Db':np.sqrt(np.mean(diff[mask]**2,axis=0)).tolist(),
                          'mean_Y_delta_percent_vs_noisy_C3':100*(mean_y/old_mean-1),
                          'noiseless_mean_Y_delta_percent_vs_C3':100*(float(y8(noiseless)[mask].mean())/float(y8(baseline)[mask].mean())-1),
                          'noiseless_std_Y8':float(y8(noiseless)[mask].std()),
                          'clipped_channels_255':int((out==255).sum()),
                          'protected_RGB_mismatches':int(np.any(out[noisy.max(axis=-1)>=208] != noisy[noisy.max(axis=-1)>=208],axis=-1).sum())}
                report['cases'].append(record)
                if noise == 4 and name in ('known_texture','color_edges_highlight','skin_shading'):
                    pictures[(name,kind)] = out
                    cv2.imwrite(str(args.output/f'{name}_{kind}.png'), cv2.cvtColor(out,cv2.COLOR_RGB2BGR))
    # JPEG is already post-C3/D3. Only evaluate extra prefilter's visible
    # smoothing response here; do not apply C3 again or call it pre-C3 data.
    source = ARTIFACT/'deep-image-audit-20261031/samples/user_shading_restored_C3_D3.jpg'
    if source.exists():
        raw = cv2.imread(str(source))
        rgb = cv2.cvtColor(cv2.resize(raw,(1280,720),interpolation=cv2.INTER_AREA),cv2.COLOR_BGR2RGB)
        # Exclude UI from the JPEG-proxy processing result.
        for noise in (2,4,8):
            out = prefilter(rgb, noise)
            out[:100,:250] = rgb[:100,:250]
            out[:120,1110:] = rgb[:120,1110:]
            cv2.imwrite(str(args.output/f'JPEG_extra_spatial_noise{noise}_proxy.png'),cv2.cvtColor(out,cv2.COLOR_RGB2BGR))
        report['JPEG_scope'] = 'Already C3/D3 output; extra smoothing proxy, not pre-lift proof'
    tiles = []
    for name in ('known_texture','color_edges_highlight','skin_shading'):
        row = []
        for kind in ('C3','pre_only','base_gain','base_gain_y3','low_cost_iir','box_base'):
            tile = cv2.cvtColor(pictures[(name,kind)],cv2.COLOR_RGB2BGR)
            tile = cv2.copyMakeBorder(tile,30,0,0,0,cv2.BORDER_CONSTANT,value=(25,25,25))
            cv2.putText(tile,kind,(8,21),cv2.FONT_HERSHEY_SIMPLEX,.52,(245,245,245),1)
            row.append(tile)
        tiles.append(np.hstack(row))
    cv2.imwrite(str(args.output/'synthetic_comparison.png'),np.vstack(tiles))
    (args.output/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for scene in ('flat80','known_texture','skin_shading','color_edges_highlight'):
        print(json.dumps([c for c in report['cases'] if c['scene']==scene and c['input_noise_sigma_RGB']==4],ensure_ascii=False))
    print(args.output/'summary.json')


if __name__ == '__main__':
    main()
