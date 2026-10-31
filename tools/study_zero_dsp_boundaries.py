"""Offline edge/rotation/stress study of the zero-DSP integer candidates."""
from pathlib import Path
import json

import cv2
import numpy as np

from study_zero_dsp_candidates import Model, ARTIFACT, components, y8


def main():
    output = ARTIFACT/'zero-dsp-research-20261031/boundaries'
    output.mkdir(parents=True, exist_ok=True)
    model = Model()
    cases = {}
    for strength in (8,16,32):
        im = np.full((160,256,3), 125, dtype=np.uint8)
        im[:,:128,0] += strength//2
        im[:,128:,0] -= strength//2
        cases[f'subtle_color_step{strength}'] = im
    yy,xx = np.indices((160,256))
    im = np.repeat((100+np.rint(20*np.sin(2*np.pi*xx/64)))[...,None],3,axis=-1).astype(np.uint8)
    cases['smooth_luma_transition'] = im
    im = np.full((160,256,3),80,dtype=np.uint8)
    im[60:80,60:196] = (204,203,202)
    im[80:100,60:196] = (209,210,211)
    cases['shoulder_highlight_rectangles'] = im
    im = np.full((160,256,3),125,dtype=np.uint8)
    im[40:120,64:192] = (130,122,125)
    cases['weak_chroma_rectangle'] = im
    im=np.empty((160,256,3),dtype=np.uint8)
    im[:]=(132,122,118)
    im[xx>yy+45]=(118,127,135)
    cases['diagonal_color_edge']=im
    rng=np.random.default_rng(20261031)
    im=np.clip(128+rng.normal(0,4,(160,256,3)),0,255).round().astype(np.uint8)
    cases['noisy_flat_rotation']=im
    results = []
    tiles=[]
    for name, im in cases.items():
        row=[]
        for kind in ('C3','pre_only','base_gain','base_gain_y3','low_cost_iir','box_base'):
            out = model.apply(im,kind,4)
            rotated = np.rot90(model.apply(np.rot90(im).copy(),kind,4),-1)
            diff = components(out)-components(rotated)
            interior = np.s_[12:-12,12:-12]
            result = {'scene':name,'candidate':kind,
                      'rotation_90_mean_abs_Y_Dr_Db':np.abs(diff[interior]).mean(axis=(0,1)).tolist(),
                      'rotation_90_max_abs_Y_Dr_Db':np.abs(diff[interior]).max(axis=(0,1)).tolist(),
                      'protected_RGB_mismatches':int(np.any(out[im.max(axis=-1)>=208] != im[im.max(axis=-1)>=208],axis=-1).sum())}
            if name.startswith('subtle_color_step'):
                dr=components(out)[80,:,1]
                low,high=float(dr[180:220].mean()),float(dr[36:76].mean())
                intermediate=(dr>low+.1*(high-low)) & (dr<low+.9*(high-low))
                result['clean_chroma_edge_transition_pixels_10_90']=int(intermediate[100:156].sum())
                result['plateau_Dr_difference']=high-low
            if name.startswith('shoulder'):
                original=model.apply(im,'C3')
                result['original_C3_max_channel_204_region']=int(original[60:80,60:196].max())
                result['candidate_max_channel_204_region']=int(out[60:80,60:196].max())
                result['nonhighlight_Y_mean_delta_vs_C3_percent']=float((y8(out)[im.max(axis=-1)<208].mean()/y8(original)[im.max(axis=-1)<208].mean()-1)*100)
            results.append(result)
            view=cv2.cvtColor(out,cv2.COLOR_RGB2BGR)
            view=cv2.copyMakeBorder(view,28,0,0,0,cv2.BORDER_CONSTANT,value=(25,25,25))
            cv2.putText(view,kind,(6,20),cv2.FONT_HERSHEY_SIMPLEX,.49,(245,245,245),1)
            row.append(view)
        tiles.append(np.hstack(row))
    cv2.imwrite(str(output/'edge_comparison.png'),np.vstack(tiles))
    main_report=json.loads((output.parent/'summary.json').read_text(encoding='utf-8'))
    limits=[]
    for kind in ('pre_only','base_gain','base_gain_y3','low_cost_iir','box_base'):
        rows=[x for x in main_report['cases'] if x['candidate']==kind]
        failures=[{'scene':r['scene'],'sigma_RGB':r['input_noise_sigma_RGB'],
                   'mean_Y_delta_percent':r['mean_Y_delta_percent_vs_noisy_C3']}
                  for r in rows if abs(r['mean_Y_delta_percent_vs_noisy_C3'])>2]
        limits.append({'candidate':kind,'mean_brightness_2pct_failures':failures,
                       'worst_mean_Y_delta_percent':max(abs(r['mean_Y_delta_percent_vs_noisy_C3']) for r in rows)})
    report={'scope':'Synthetic boundary and rotation diagnostics; not board validation',
            'results':results,'brightness_stress':limits}
    (output/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'color_steps':[x for x in results if x['scene'].startswith('subtle')],
                      'brightness_stress':limits},ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
