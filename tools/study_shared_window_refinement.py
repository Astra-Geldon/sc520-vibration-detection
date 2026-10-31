"""Research-only correction of shared3_pre DC bias and shoulder overshoot.

No RTL, TD, programming or device capture. Uniform DC and shoulder guarantees
are numerical properties, not proof of real900 video quality or resources.
"""
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np

from study_shared_window import apply_shared
from study_zero_dsp_candidates import ARTIFACT, Model, components, scenes, y8


def refined(rgb, model, noise=4, shoulder_guard=True, diagnostics=False):
    q = rgb.astype(np.int64)
    y = y8(rgb).astype(np.int64)
    dr, db = q[...,0]-q[...,1], q[...,2]-q[...,1]
    protected = q.max(axis=-1)>=208
    values = np.stack((y,dr,db),axis=-1)
    vp = np.pad(values,((1,1),(1,1),(0,0)),mode='edge')
    pp = np.pad(protected,((1,1),(1,1)),mode='edge')
    acc = np.zeros_like(values)
    yt = min(24,max(6,int(noise*3)))
    ct = min(48,max(12,int(noise*6)))
    for iy,wy in enumerate((1,2,1)):
        for ix,wx in enumerate((1,2,1)):
            n = vp[iy:iy+q.shape[0],ix:ix+q.shape[1]]
            valid = np.abs(n[...,0]-y)<=yt
            valid &= (np.abs(n[...,1]-dr)<=ct) & (np.abs(n[...,2]-db)<=ct)
            valid &= ~pp[iy:iy+q.shape[0],ix:ix+q.shape[1]] & ~protected
            acc += (wy*wx)*np.where(valid[...,None],n,values)
    # sum(weights)=16, so the integer weighted sums already represent Q4.
    dyq = ((y*16+3*acc[...,0]+2)>>2)-y*16
    ddrq,ddbq = acc[...,1]-dr*16,acc[...,2]-db*16
    dgq = dyq-((77*ddrq+29*ddbq+128)>>8)
    delta = np.stack((dgq+ddrq,dgq,dgq+ddbq),axis=-1)
    trial = (q*16+delta+8)>>4
    legal = np.all((trial>=0)&(trial<=255),axis=-1)
    shoulder = (~protected)&(trial.max(axis=-1)>=208)
    allowed = legal & ~protected
    if shoulder_guard:
        allowed &= ~shoulder
    clean = np.where(allowed[...,None],trial,q).astype(np.uint8)
    out = model.apply(clean,'C3')
    assert np.array_equal(out[protected],rgb[protected])
    if shoulder_guard:
        assert np.all(out[~protected]<=208)
    if diagnostics:
        return out,{'legal_fallback_pixels':int((~legal&~protected).sum()),
                    'shoulder_fallback_pixels':int((shoulder&legal).sum()),
                    'protected_pixels':int(protected.sum()),
                    'input_pixels':int(y.size),'prefilter_changed_pixels':int(np.any(clean!=rgb,axis=-1).sum())}
    return out


def main():
    output = ARTIFACT/'zero-dsp-followup-20261031/refinement'
    output.mkdir(parents=True,exist_ok=True)
    model = Model()
    rng = np.random.default_rng(20261101)
    report = {'scope':__doc__,'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'noise_scope':'Known synthetic profile, not current900 calibration','DSP_limit':34,
              'TD_or_board_operations':False,'cases':[],'counterexamples':[],
              'resource_note':'Same two50-bit rows proposed; delta reconstruction needs signed21-bit constant arithmetic under independent bounds; mapping unverified'}
    pictures = []
    for name,clean in scenes().items():
        mask = clean.max(axis=-1)<208
        mask[:10] = mask[-10:] = False
        mask[:,:10] = mask[:,-10:] = False
        row=[]
        for sigma in (2,4,8):
            noisy = np.clip(clean.astype(float)+rng.normal(0,sigma,clean.shape),0,255).round().astype(np.uint8)
            original = model.apply(noisy,'C3')
            for kind in ('C3','old_shared3','delta_guard'):
                if kind=='C3':
                    run=lambda im:model.apply(im,'C3')
                elif kind=='old_shared3':
                    run=lambda im:apply_shared(im,model,sigma,3,False)
                else:
                    run=lambda im:refined(im,model,sigma)
                out,noiseless=run(noisy),run(clean)
                diff=components(out)-components(noiseless)
                record={'scene':name,'sigma_RGB':sigma,'candidate':kind,
                        'noise_RMSE_Y_Dr_Db':np.sqrt(np.mean(diff[mask]**2,axis=0)).tolist(),
                        'mean_Y_delta_percent':100*(float(y8(out)[mask].mean())/float(y8(original)[mask].mean())-1),
                        'noiseless_std_Y8':float(y8(noiseless)[mask].std())}
                if kind=='delta_guard':
                    _,record['diagnostics']=refined(noisy,model,sigma,diagnostics=True)
                report['cases'].append(record)
                if sigma==4 and name in ('known_texture','skin_shading','color_edges_highlight'):
                    tile=cv2.cvtColor(out,cv2.COLOR_RGB2BGR)
                    tile=cv2.copyMakeBorder(tile,28,0,0,0,cv2.BORDER_CONSTANT,value=(25,25,25))
                    cv2.putText(tile,kind,(8,20),cv2.FONT_HERSHEY_SIMPLEX,.5,(245,245,245),1)
                    row.append(tile)
        if row:
            pictures.append(np.hstack(row))
    # Exhaustive constant-color reconstruction from the zero-delta equations.
    g,b=np.indices((256,256),dtype=np.int64)
    mismatches=0
    for r in range(256):
        y=(77*r+150*g+29*b+128)>>8
        dr,db=r-g,b-g
        dyq=((16*y+3*16*y+2)>>2)-16*y
        ddrq,ddbq=16*dr-16*dr,16*db-16*db
        dgq=dyq-((77*ddrq+29*ddbq+128)>>8)
        trial=(np.stack((np.full_like(g,r)*16+dgq+ddrq,g*16+dgq,b*16+dgq+ddbq),axis=-1)+8)>>4
        original=np.stack((np.full_like(g,r),g,b),axis=-1)
        mismatches+=int(np.any(trial!=original,axis=-1).sum())
    assert mismatches==0
    report['uniform_all_RGB8']={'colors':256**3,'reconstruction_mismatches':mismatches,
                              'scope':'Exhaustive zero-delta equations; sampled full-window path also checked below'}
    samples=0
    for color in ((1,0,2),(17,16,18),(129,128,130),(0,0,0),(207,207,207),(208,208,208),(255,0,255)):
        im=np.full((7,7,3),color,np.uint8)
        corrected=refined(im,model,4)
        assert np.array_equal(corrected,model.apply(im,'C3'))
        report['counterexamples'].append({'uniform_RGB':color,'original_C3':model.apply(im,'C3')[3,3].tolist(),
                                          'old_shared3':apply_shared(im,model,4,3,False)[3,3].tolist(),
                                          'corrected':corrected[3,3].tolist()})
        samples+=1
    report['uniform_full_window_samples']=samples
    im=np.full((7,7,3),(207,195,195),np.uint8); im[3,3]=(207,207,207)
    report['shoulder_counterexample']={'original_C3':model.apply(im,'C3')[3,3].tolist(),
        'old_shared3':apply_shared(im,model,4,3,False)[3,3].tolist(),
        'delta_without_guard':refined(im,model,4,False)[3,3].tolist(),
        'delta_guard':refined(im,model,4)[3,3].tolist()}
    stress=[]
    for sigma in (2,4,8):
        for limit in (208,256):
            im=rng.integers(0,limit,(384,512,3),dtype=np.uint8)
            out,diag=refined(im,model,sigma,diagnostics=True)
            rotated=np.rot90(refined(np.rot90(im).copy(),model,sigma),-1)
            assert np.array_equal(out,rotated)
            stress.append({'sigma':sigma,'random_RGB_upper_exclusive':limit,'pixels':384*512,
                           'rotation90_RGB_mismatches':0,**diag})
    report['stress']=stress
    motion=np.full((128,192,3),(92,76,62),np.uint8)
    motion[32:96,50:80]=(207,195,195);motion[48:80,110:142]=(230,235,240)
    translations=[]
    for dx,dy in ((3,0),(0,4),(5,3)):
        moved=np.roll(motion,(dy,dx),(0,1))
        out=refined(moved,model,4)
        expected=np.roll(refined(motion,model,4),(dy,dx),(0,1))
        mismatch=int(np.any(out[10:-10,10:-10]!=expected[10:-10,10:-10],axis=-1).sum())
        assert mismatch==0
        translations.append({'dx':dx,'dy':dy,'interior_mismatches':mismatch})
    report['translation_checks']=translations
    report['motion_scope']='Integer translation of synthetic current frames; no state/history in this model. Does not verify real motion, threshold flicker or hardware timing.'
    (output/'summary.json').write_bytes((json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8'))
    cv2.imwrite(str(output/'comparison.png'),np.vstack(pictures))
    print(json.dumps({'texture_sigma4':[x for x in report['cases'] if x['scene']=='known_texture' and x['sigma_RGB']==4],
                      'uniform':report['uniform_all_RGB8'],'shoulder':report['shoulder_counterexample'],
                      'stress_pixels':sum(x['pixels'] for x in stress)},ensure_ascii=False,indent=2),flush=True)


if __name__=='__main__':
    main()
