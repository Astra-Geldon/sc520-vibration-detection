"""Study trusted archived UGREEN HDMI captures, never opens a device.

Input is already processed original1991/C0 HDMI and MJPEG/PNG, not RAW.
"""
from pathlib import Path
import hashlib
import json
import cv2
import numpy as np

BASE = Path('D:/FPGA/codex/_build/20261029project/stage0-ugreen-valid-20261030')
OUT = Path(__file__).resolve().parents[1].parent / "_build" / Path(__file__).resolve().parents[1].name / "zero-dsp-research-20261031/archive-noise"
ROI = (100, 120, 1180, 650)


def rgb_load(path):
    bgr = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if bgr is None:
        raise RuntimeError(path)
    native = cv2.resize(bgr, (1280, 720), interpolation=cv2.INTER_AREA) if bgr.shape[:2] != (720,1280) else bgr
    return cv2.cvtColor(native, cv2.COLOR_BGR2RGB), bgr.shape[:2]


def analyze(scene):
    files = sorted((BASE/scene).glob('frame_*.png'))
    meta = json.loads((BASE/scene/'summary.json').read_text(encoding='utf-8'))
    assert meta['device'] == 'UGREEN 25854' and meta['source'] == 'DirectShow video=UGREEN 25854'
    assert len(files) == 60
    sums = squares = prev = mean_rgb = None
    means = []
    frame_grids = []
    diffs, diffs_centered = [], []
    seen, decoded_hashes, file_hashes = {}, [], []
    adjacent_repeats, all_repeats = [], []
    sizes = []
    first_frame = None
    x0,y0,x1,y1 = ROI
    for i,p in enumerate(files):
        rgb, size = rgb_load(p)
        sizes.append(size)
        if first_frame is None:
            first_frame = rgb
        digest = hashlib.sha256(rgb.tobytes()).hexdigest()
        if digest in seen:
            all_repeats.append([i,seen[digest]])
        if decoded_hashes and digest == decoded_hashes[-1]:
            adjacent_repeats.append(i)
        seen.setdefault(digest,i)
        decoded_hashes.append(digest)
        file_hashes.append({'name':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
        q = rgb[y0:y1,x0:x1].astype(np.float64)
        # OpenCV's encoded YCrCb statistics include integer conversion noise;
        # use float Y and channel differences as additional independent axes.
        encoded = cv2.cvtColor(rgb[y0:y1,x0:x1],cv2.COLOR_RGB2YCrCb).astype(np.float64)
        r,g,b = [q[...,j] for j in range(3)]
        axes = np.concatenate([encoded, ((77*r+150*g+29*b)/256)[...,None],
                               (r-g)[...,None],(b-g)[...,None]],axis=-1)
        if sums is None:
            sums, squares, mean_rgb = np.zeros_like(axes),np.zeros_like(axes),np.zeros_like(q)
        sums += axes
        squares += axes*axes
        mean_rgb += q
        means.append(axes.mean(axis=(0,1)))
        hh,ww = axes.shape[:2]
        frame_grids.append([[axes[row*hh//6:(row+1)*hh//6,col*ww//10:(col+1)*ww//10].mean(axis=(0,1))
                             for col in range(10)] for row in range(6)])
        if prev is not None:
            diff = axes-prev
            diffs.append((diff*diff).mean(axis=(0,1)))
            centered = diff-diff.mean(axis=(0,1))
            diffs_centered.append((centered*centered).mean(axis=(0,1)))
        prev = axes

    n = len(files)
    mean = sums/n
    variance = np.maximum(0,(squares-sums*sums/n)/(n-1))
    mean_rgb /= n
    names = ['Y8_opencv','Cr8_opencv','Cb8_opencv','Y_float77_150_29','R_minus_G','B_minus_G']
    gmeans = np.asarray(means)
    temporal_sigma = np.sqrt(variance.mean(axis=(0,1)))
    adjacent_sigma = np.sqrt(np.mean(diffs,axis=0)/2)
    centered_sigma = np.sqrt(np.mean(diffs_centered,axis=0)/2)
    spatial_sigma = mean.std(axis=(0,1))
    grid_movie = np.asarray(frame_grids)
    grid_diff = np.diff(grid_movie,axis=0)
    grid_mean_removed = grid_movie-grid_movie.mean(axis=(1,2),keepdims=True)
    grid_diff_centered = np.diff(grid_mean_removed,axis=0)
    cell_values=[]
    hh,ww = mean.shape[:2]
    for row in range(6):
        for col in range(10):
            a = np.s_[row*hh//6:(row+1)*hh//6,col*ww//10:(col+1)*ww//10]
            cm = mean_rgb[a].mean(axis=(0,1))
            cell_values.append({'row':row,'col':col,'RGB':cm.tolist(),
                                'R_over_G':float(cm[0]/cm[1]),'B_over_G':float(cm[2]/cm[1]),
                                'YCrCb':mean[a].mean(axis=(0,1))[:3].tolist()})
    np.savez_compressed(OUT/f'{scene}_maps.npz',mean_RGB=mean_rgb.astype(np.float32),
                        mean_axes=mean.astype(np.float32),std_axes=np.sqrt(variance).astype(np.float32))
    # Native-size mean image with ROI replaced by true temporal mean.
    shown = first_frame.copy()
    shown[y0:y1,x0:x1] = np.rint(mean_rgb).astype(np.uint8)
    cv2.imwrite(str(OUT/f'{scene}_temporal_mean.png'),cv2.cvtColor(shown,cv2.COLOR_RGB2BGR))
    cols = np.asarray([c['RGB'] for c in cell_values]).reshape(6,10,3)
    result={'scene':scene,'source':meta['source'],'frame_count':n,
            'file_sizes_yx':sorted(set(sizes)),'analysis_size':[1280,720],'roi_xyxy':ROI,
            'source_exposure_context':'Original A+Logo, requested exposure1991 AG160; pre-C3 baseline, not current900/C3',
            'format_scope':'Processed gamma/shading HDMI RGB, captured MJPEG for flat; not sensor RAW',
            'unique_decoded_frames':len(seen),'adjacent_exact_repeats':adjacent_repeats,
            'all_exact_repeat_pairs':all_repeats,'axis_order':names,
            'ROI_mean':mean.mean(axis=(0,1)).tolist(),
            'RMS_temporal_sigma_unbiased':temporal_sigma.tolist(),
            'adjacent_diff_RMS_div_sqrt2':adjacent_sigma.tolist(),
            'adjacent_diff_after_ROI_mean_removal_RMS_div_sqrt2':centered_sigma.tolist(),
            'global_mean_over_time_std':gmeans.std(axis=0,ddof=1).tolist(),
            'global_mean_over_time_peak_to_peak':np.ptp(gmeans,axis=0).tolist(),
            'grid_adjacent_change_abs_p99':np.percentile(np.abs(grid_diff),99,axis=(0,1,2)).tolist(),
            'grid_adjacent_change_global_mean_removed_abs_p99':np.percentile(np.abs(grid_diff_centered),99,axis=(0,1,2)).tolist(),
            'grid_adjacent_change_global_mean_removed_abs_max':np.max(np.abs(grid_diff_centered),axis=(0,1,2)).tolist(),
            'temporal_mean_spatial_sigma':spatial_sigma.tolist(),
            'temporal_variance_fraction_of_single_frame_spatial_variance':
                (variance.mean(axis=(0,1))/(variance.mean(axis=(0,1))+spatial_sigma**2)).tolist(),
            'grid_6x10':cell_values,
            'grid_RGB_column_means':cols.mean(axis=0).tolist(),
            'grid_R_over_G_range':[min(c['R_over_G'] for c in cell_values),max(c['R_over_G'] for c in cell_values)],
            'grid_B_over_G_range':[min(c['B_over_G'] for c in cell_values),max(c['B_over_G'] for c in cell_values)],
            'frame_file_hashes':file_hashes}
    np.savez_compressed(OUT/f'{scene}_timeline.npz',global_mean=gmeans,grid_mean=grid_movie)
    (OUT/f'{scene}_summary.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if not k.startswith('grid_') and k!='frame_file_hashes'},indent=2))
    return result


if __name__ == '__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    results={scene:analyze(scene) for scene in ['flat','dark']}
    (OUT/'summary.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
