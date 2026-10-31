"""Paired offline C3/candidate response on verified saved C0 HDMI video.

No live device access, RTL edit, TD build or programming. Camera state is
confirmed by the capture record/user/visual review, not sensor readback.
"""
import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np

from study_shared_window_refinement import refined
from study_zero_dsp_candidates import ARTIFACT, Model


def channels(rgb):
    return np.concatenate((cv2.cvtColor(rgb,cv2.COLOR_RGB2YCrCb),rgb),axis=-1).astype(np.float64)


def parse_roi(text):
    name,coords=text.split(':',1)
    x0,y0,x1,y1=map(int,coords.split(','))
    if not name or not (1<=x0<x1<=1279 and 1<=y0<y1<=719):
        raise ValueError('ROI needs real one-pixel surrounding context inside1280x720: '+text)
    return name,(x0,y0,x1,y1)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture',type=Path,required=True)
    parser.add_argument('--roi',action='append',required=True)
    parser.add_argument('--stride',type=int,default=2)
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    capture=json.loads((args.capture/'summary.json').read_text(encoding='utf-8'))
    assert capture['complete'] and capture['state_claim']['C']==0
    assert capture['device']['name']=='UGREEN 25854'
    assert 'vid_2b89&pid_5854' in capture['device']['path'].lower()
    assert args.stride>=1
    rois=dict(parse_roi(r) for r in args.roi)
    selected=capture['frames'][::args.stride]
    assert len(selected)>=20
    output=args.output or ARTIFACT/'quality-real900-research-20261031/analysis'/args.capture.name
    output.mkdir(parents=True,exist_ok=True)
    model=Model()
    state={}
    previews={name:[] for name in rois}
    protected_counts={name:0 for name in rois}
    report={'scope':__doc__,'capture_path':str(args.capture.resolve()),
            'capture_summary_SHA256':hashlib.sha256((args.capture/'summary.json').read_bytes()).hexdigest(),
            'source_state_claim':capture['state_claim'],'actual_capture_fourcc':capture.get('reported_fourcc'),
            'original_saved_frames':len(capture['frames']),'paired_selected_frames':len(selected),
            'selected_frame_stride':args.stride,'axes':['Y8_OpenCV','Cr8_OpenCV','Cb8_OpenCV','R','G','B'],
            'candidate_profiles':'Synthetic profile2/4/8 gate choices, not measured sensor sigma',
            'data_limits':'Processed HDMI RGB; capture conversion/range and time variation included. No RAW SNR or matched clean ground truth. Current E1 fast AWB differs from source measurement image.',
            'temporal_sampling_limits':capture['timestamp_limit'],
            'source_SHA256':{},'rois':{}}
    for index,item in enumerate(selected):
        path=args.capture/item['file']
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest.lower()==item['SHA256'].lower()
        report['source_SHA256'][item['file']]=digest
        bgr=cv2.imread(str(path))
        assert bgr is not None and bgr.shape==(720,1280,3)
        rgb=cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
        for name,(x0,y0,x1,y1) in rois.items():
            crop=rgb[y0-1:y1+1,x0-1:x1+1]
            raw=crop[1:-1,1:-1]
            protected=raw.max(axis=-1)>=208
            protected_counts[name]+=int(protected.sum())
            for kind in ('C0','C3','P2','P4','P8'):
                diagnostics=None
                if kind=='C0':
                    out=raw
                elif kind=='C3':
                    out=model.apply(crop,'C3')[1:-1,1:-1]
                else:
                    full,diagnostics=refined(crop,model,int(kind[1:]),diagnostics=True)
                    out=full[1:-1,1:-1]
                    assert np.array_equal(out[protected],raw[protected])
                a=channels(out)
                frame_mean=a.mean(axis=(0,1))
                centered=a-frame_mean
                key=(name,kind)
                if key not in state:
                    state[key]={'sum':np.zeros_like(a),'squares':np.zeros_like(a),
                                'centered_sum':np.zeros_like(a),'centered_squares':np.zeros_like(a),
                                'frame_means':[],'clipped_channel_values':0,'diagnostics':{},'neighbor_products':{}}
                s=state[key]
                s['sum']+=a; s['squares']+=a*a
                s['centered_sum']+=centered;s['centered_squares']+=centered*centered
                s['frame_means'].append(frame_mean.tolist())
                s['clipped_channel_values']+=int(np.count_nonzero(out==255))
                if diagnostics:
                    for k,v in diagnostics.items():s['diagnostics'][k]=s['diagnostics'].get(k,0)+v
                if kind in ('C0','C3'):
                    for axis in (0,1):
                        for lag in (1,2,4,8):
                            sa=[slice(None),slice(None)];sb=sa.copy()
                            sa[axis]=slice(lag,None);sb[axis]=slice(None,-lag)
                            aa=centered[tuple(sa)][...,:3];bb=centered[tuple(sb)][...,:3]
                            k=(axis,lag)
                            prod=(aa*bb).sum(axis=(0,1))
                            s['neighbor_products'][k]=s['neighbor_products'].get(k,0)+prod
                if index==len(selected)//2:
                    view=cv2.cvtColor(out,cv2.COLOR_RGB2BGR)
                    view=cv2.copyMakeBorder(view,28,0,0,0,cv2.BORDER_CONSTANT,value=(25,25,25))
                    cv2.putText(view,kind,(7,20),cv2.FONT_HERSHEY_SIMPLEX,.55,(245,245,245),1)
                    previews[name].append(view)
        if (index+1)%10==0:print('processed',index+1,'/',len(selected),flush=True)
    for name,coords in rois.items():
        x0,y0,x1,y1=coords
        n=len(selected)
        group={'coordinates_xyxy':coords,'source_protected_fraction':protected_counts[name]/(n*(x1-x0)*(y1-y0)),
               'candidates':{}}
        for kind in ('C0','C3','P2','P4','P8'):
            s=state[(name,kind)]
            mean=s['sum']/n
            variance=np.maximum(0,(s['squares']-s['sum']*s['sum']/n)/(n-1))
            centered_variance=np.maximum(0,(s['centered_squares']-s['centered_sum']*s['centered_sum']/n)/(n-1))
            means=mean.mean(axis=(0,1))
            result={'mean_YCrCbRGB':means.tolist(),'temporal_RMS_sigma':np.sqrt(variance.mean(axis=(0,1))).tolist(),
                    'global_mean_removed_temporal_RMS_sigma':np.sqrt(centered_variance.mean(axis=(0,1))).tolist(),
                    'mean_image_spatial_sigma':mean.std(axis=(0,1)).tolist(),
                    'Y_frame_mean_peak_to_peak':float(np.ptp(np.array(s['frame_means'])[:,0])),
                    'clipped_channel_values':s['clipped_channel_values'],
                    'mean_R_over_G':float(means[3]/means[4]),'mean_B_over_G':float(means[5]/means[4])}
            if s['diagnostics']:
                result['candidate_diagnostics_including_1px_context']=s['diagnostics']
            if kind in ('C0','C3'):
                result['centered_temporal_neighbor_correlation']={}
                for (axis,lag),product in s['neighbor_products'].items():
                    sa=[slice(None),slice(None)];sb=sa.copy()
                    sa[axis]=slice(lag,None);sb[axis]=slice(None,-lag)
                    sa,sb=tuple(sa),tuple(sb)
                    pair_count=centered_variance[sa].shape[0]*centered_variance[sa].shape[1]
                    covariance=(product-(s['centered_sum'][sa][...,:3]*s['centered_sum'][sb][...,:3]).sum(axis=(0,1))/n)/((n-1)*pair_count)
                    scale=np.sqrt(centered_variance[sa][...,:3].mean(axis=(0,1))*centered_variance[sb][...,:3].mean(axis=(0,1)))
                    rho=np.divide(covariance,scale,out=np.zeros_like(covariance),where=scale>0)
                    result['centered_temporal_neighbor_correlation'][('V' if axis==0 else 'H')+str(lag)]=rho.tolist()
            group['candidates'][kind]=result
            cv2.imwrite(str(output/(name+'_'+kind+'_mean.png')),cv2.cvtColor(np.rint(mean[...,3:]).clip(0,255).astype(np.uint8),cv2.COLOR_RGB2BGR))
        reference=group['candidates']['C3']
        for kind,item in group['candidates'].items():
            item['mean_Y_delta_percent_vs_C3']=100*(item['mean_YCrCbRGB'][0]/reference['mean_YCrCbRGB'][0]-1)
            item['mean_CrCb_delta_codes_vs_C3']=(np.array(item['mean_YCrCbRGB'][1:3])-np.array(reference['mean_YCrCbRGB'][1:3])).tolist()
        report['rois'][name]=group
        cv2.imwrite(str(output/(name+'_comparison.png')),np.hstack(previews[name]))
    (output/'summary.json').write_bytes((json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8'))
    print('Saved',output,flush=True)


if __name__=='__main__':
    main()
