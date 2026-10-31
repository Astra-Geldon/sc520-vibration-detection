"""Response proxy on trusted old1991/C0 processed HDMI captures.

Does not open a camera or program the board. This is NOT current900 data,
sensor RAW, a bit-exact pre-C3 tap, or a measured sensor SNR claim.
"""
from pathlib import Path
import hashlib
import json

import cv2
import numpy as np

from study_shared_window import apply_shared
from study_shared_window_refinement import refined
from study_zero_dsp_candidates import ARTIFACT, Model, y8


def axes(rgb):
    q = rgb.astype(np.float64)
    encoded = cv2.cvtColor(rgb, cv2.COLOR_RGB2YCrCb).astype(np.float64)
    return np.concatenate((encoded, q), axis=-1)


def main():
    source = ARTIFACT/'stage0-ugreen-valid-20261030'
    output = ARTIFACT/'zero-dsp-followup-20261031/refinement/real-archive'
    output.mkdir(parents=True, exist_ok=True)
    roi = (100,120,1180,650)
    model = Model()
    report = {'scope': __doc__, 'roi_xyxy': roi, 'source_context': 'old1991/AG160/C0 HDMI, already Gamma/shading/capture conversion',
              'current900_or_matched_current_AWB': False, 'scenes': {}, 'source_SHA256': {}}
    for scene in ('flat','dark'):
        files = sorted((source/scene).glob('frame_*.png'))
        meta = json.loads((source/scene/'summary.json').read_text(encoding='utf-8'))
        assert meta['device']=='UGREEN 25854' and meta['source']=='DirectShow video=UGREEN 25854'
        assert len(files)==60
        state = {}
        protected_mismatch = {k:0 for k in ('C3','old_sigma4','delta_sigma2','delta_sigma4','delta_sigma8')}
        protected_count = 0
        example = []
        for index, path in enumerate(files):
            bgr = cv2.imread(str(path))
            assert bgr is not None
            if bgr.shape[:2] != (720,1280):
                bgr = cv2.resize(bgr,(1280,720),interpolation=cv2.INTER_AREA)
            rgb = cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
            x0,y0,x1,y1 = roi
            # One-pixel real context around ROI: no synthetic ROI-edge taps.
            crop = rgb[y0-1:y1+1,x0-1:x1+1]
            center = crop[1:-1,1:-1]
            protected = center.max(axis=-1)>=208
            protected_count += int(protected.sum())
            for kind in protected_mismatch:
                if kind=='C3':
                    out = model.apply(crop,'C3')
                elif kind.startswith('old_'):
                    out = apply_shared(crop,model,int(kind[-1]),3,False)
                else:
                    out = refined(crop,model,int(kind[-1]))
                out = out[1:-1,1:-1]
                protected_mismatch[kind] += int(np.any(out[protected] != center[protected],axis=-1).sum())
                a = axes(out)
                frame_mean = a.mean(axis=(0,1))
                centered = a-frame_mean
                if kind not in state:
                    state[kind] = {'sum':np.zeros_like(a),'squares':np.zeros_like(a),
                                   'centered_sum':np.zeros_like(a),'centered_squares':np.zeros_like(a),
                                   'frame_means':[]}
                st = state[kind]
                st['sum'] += a; st['squares'] += a*a
                st['centered_sum'] += centered; st['centered_squares'] += centered*centered
                st['frame_means'].append(frame_mean.tolist())
                if index==30:
                    view = cv2.cvtColor(out,cv2.COLOR_RGB2BGR)
                    view = cv2.copyMakeBorder(view,28,0,0,0,cv2.BORDER_CONSTANT,value=(25,25,25))
                    cv2.putText(view,scene+' '+kind,(8,20),cv2.FONT_HERSHEY_SIMPLEX,.6,(245,245,245),1)
                    example.append(view)
            report['source_SHA256'][scene+'/'+path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
            if (index+1)%10==0:
                print(scene,index+1,'/60',flush=True)
        result = {'frames':60,'axes':['Y8_OpenCV','Cr8_OpenCV','Cb8_OpenCV','R','G','B'],
                  'input_protected_fraction':protected_count/(60*(roi[2]-roi[0])*(roi[3]-roi[1])),
                  'candidates':{}}
        for kind,st in state.items():
            n = len(files)
            mean = st['sum']/n
            variance = np.maximum(0,(st['squares']-st['sum']*st['sum']/n)/(n-1))
            centered_var = np.maximum(0,(st['centered_squares']-st['centered_sum']*st['centered_sum']/n)/(n-1))
            means = mean.mean(axis=(0,1))
            result['candidates'][kind] = {
                'means_YCrCbRGB': means.tolist(),
                'temporal_RMS_sigma': np.sqrt(variance.mean(axis=(0,1))).tolist(),
                'global_mean_removed_temporal_RMS_sigma':np.sqrt(centered_var.mean(axis=(0,1))).tolist(),
                'temporal_mean_image_spatial_sigma':mean.std(axis=(0,1)).tolist(),
                'frame_Y_mean_peak_to_peak':float(np.ptp(np.array(st['frame_means'])[:,0])),
                'mean_R_over_G':float(means[3]/means[4]),'mean_B_over_G':float(means[5]/means[4]),
                'protected_mismatches':protected_mismatch[kind]}
            cv2.imwrite(str(output/(scene+'_'+kind+'_mean.png')),cv2.cvtColor(np.clip(np.rint(mean[...,3:]),0,255).astype(np.uint8),cv2.COLOR_RGB2BGR))
        reference = result['candidates']['C3']
        for kind,item in result['candidates'].items():
            item['mean_Y_delta_percent'] = 100*(item['means_YCrCbRGB'][0]/reference['means_YCrCbRGB'][0]-1)
            item['mean_CrCb_delta_codes'] = (np.array(item['means_YCrCbRGB'][1:3])-np.array(reference['means_YCrCbRGB'][1:3])).tolist()
        report['scenes'][scene] = result
        cv2.imwrite(str(output/(scene+'_comparison.png')),np.hstack(example))
    (output/'summary.json').write_bytes((json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8'))
    for scene,item in report['scenes'].items():
        print(scene,json.dumps(item['candidates'],ensure_ascii=False),flush=True)


if __name__=='__main__':
    main()
