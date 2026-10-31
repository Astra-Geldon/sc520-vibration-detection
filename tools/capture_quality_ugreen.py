"""Capture research sequences ONLY from identity-checked FPGA HDMI UGREEN.

--list enumerates devices without opening one. Other use requires a confirmed
scene/OSD state; the recorded state is a user claim, not I2C/JTAG readback.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import time

import cv2
from cv2_enumerate_cameras import enumerate_cameras


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent/'_build'/ROOT.name/'quality-real900-research-20261031'


def identity(camera):
    return {'name':camera.name,'path':camera.path,'index':camera.index,'backend':'DirectShow'}


def target():
    matches = [c for c in enumerate_cameras(cv2.CAP_DSHOW)
               if c.name == 'UGREEN 25854' and 'vid_2b89&pid_5854' in c.path.lower()]
    if len(matches) != 1:
        raise RuntimeError('Exactly one UGREEN 25854 / VID_2B89&PID_5854 is required; no camera fallback.')
    return matches[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list',action='store_true',help='Verify target identity, never open a video device')
    parser.add_argument('--scene',choices=('flat','face','dark','motion'))
    parser.add_argument('--exposure',type=int,choices=(900,1200,1600,1991))
    parser.add_argument('--tone',type=int,choices=(0,3))
    parser.add_argument('--bit',type=Path)
    parser.add_argument('--sha256')
    parser.add_argument('--state-note',help='Required: how current scene/exposure/C state was confirmed')
    parser.add_argument('--count',type=int,default=60)
    parser.add_argument('--warmup',type=int,default=150)
    parser.add_argument('--output',type=Path)
    args = parser.parse_args()
    camera = target()
    if args.list:
        print(json.dumps({'target':identity(camera),'video_device_opened':False},ensure_ascii=False,indent=2))
        return
    if any(x is None for x in (args.scene,args.exposure,args.tone,args.bit,args.sha256,args.state_note)):
        parser.error('Capture requires --scene, --exposure, --tone, --bit, --sha256 and --state-note.')
    if not 2 <= args.count <= 300 or not 120 <= args.warmup <= 300:
        parser.error('count must be 2..300; warmup must be 120..300 frames.')
    digest = hashlib.sha256(args.bit.read_bytes()).hexdigest()
    if digest.lower() != args.sha256.lower():
        raise RuntimeError('Specified source bit SHA256 mismatch; video device has not been opened.')
    output = args.output or BASE/(args.scene+'-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
    output.mkdir(parents=True,exist_ok=False)
    report = {'scope':'Processed HDMI UVC video decoded to RGB; actual delivered FourCC recorded separately, not RAW or an internal bit-exact tap',
              'device':identity(camera),'requested_size':[1280,720],'requested_fps':30,
              'requested_fourcc':'MJPG','warmup_frames':args.warmup,
              'state_claim':{'exposure':args.exposure,'C':args.tone,'scene':args.scene,'note':args.state_note},
              'state_source':'User/OSD confirmation; no sensor I2C readback or programmed-bit readback',
              'source_bit_file':str(args.bit.resolve()),'source_bit_SHA256':digest,
              'started_utc':datetime.now(timezone.utc).isoformat(),'frames':[],
              'complete':False,'human_review_of_contact_sheet_required':True}
    cap = cv2.VideoCapture(camera.index,cv2.CAP_DSHOW)
    seen = set()
    previews = []
    buffered = []
    try:
        if not cap.isOpened():
            raise RuntimeError('UGREEN unavailable or occupied; close capture preview. No fallback.')
        after = target()
        if after.path != camera.path or after.index != camera.index or cap.getBackendName() != 'DSHOW':
            raise RuntimeError('Device enumeration/backend changed; stop to avoid wrong camera.')
        cap.set(cv2.CAP_PROP_FOURCC,cv2.VideoWriter_fourcc(*'MJPG'))
        cap.set(cv2.CAP_PROP_FRAME_WIDTH,1280)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT,720)
        cap.set(cv2.CAP_PROP_FPS,30)
        report['reported_fps'] = cap.get(cv2.CAP_PROP_FPS)
        fourcc = int(cap.get(cv2.CAP_PROP_FOURCC))
        report['reported_fourcc'] = ''.join(chr((fourcc>>(8*i))&255) for i in range(4))
        for index in range(args.warmup+args.count):
            ok, frame = cap.read()
            read_ns = time.monotonic_ns()
            if not ok:
                raise RuntimeError('UGREEN stopped delivering frames.')
            if index < args.warmup:
                continue
            if frame.shape != (720,1280,3):
                raise RuntimeError('Unexpected capture dimensions; resizing measurement data is not allowed: '+str(frame.shape))
            # Keep PNG encoding and hashing out of the acquisition loop.
            # At default60 frames this buffers about166MB of BGR pixels.
            buffered.append((frame.copy(),read_ns))
        cap.release()
        intervals = [(b[1]-a[1])/1e6 for a,b in zip(buffered,buffered[1:])]
        report['host_read_intervals_ms'] = {'mean':sum(intervals)/len(intervals),
                                            'minimum':min(intervals),'maximum':max(intervals)}
        report['host_read_span_seconds'] = (buffered[-1][1]-buffered[0][1])/1e9
        report['PNG_encoding_after_acquisition'] = True
        for number,(frame,read_ns) in enumerate(buffered):
            path = output/f'frame_{number:03d}.png'
            if not cv2.imwrite(str(path),frame):
                raise RuntimeError('PNG write failed: '+str(path))
            decoded_hash = hashlib.sha256(frame.tobytes()).hexdigest()
            report['frames'].append({'file':path.name,'SHA256':hashlib.sha256(path.read_bytes()).hexdigest(),
                                     'decoded_BGR_SHA256':decoded_hash,'read_monotonic_ns':read_ns,
                                     'repeated_decoded_frame':decoded_hash in seen})
            seen.add(decoded_hash)
            if number in (0,args.count//2,args.count-1):
                previews.append(cv2.resize(frame,(640,360),interpolation=cv2.INTER_AREA))
        report['complete'] = True
        if previews:
            import numpy as np
            cv2.imwrite(str(output/'contact_sheet.png'),np.hstack(previews))
    except Exception as exc:
        report['error'] = str(exc)
        raise
    finally:
        cap.release()
        report['unique_decoded_frames'] = len(seen)
        report['finished_utc'] = datetime.now(timezone.utc).isoformat()
        report['timestamp_limit']='Read times are host timestamps, not independent sensor timestamps.'
        (output/'summary.json').write_bytes((json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8'))
    print(json.dumps({'complete':True,'frames':len(report['frames']),'output':str(output),
                      'unique_decoded_frames':len(seen),'review_contact_sheet_before_analysis':True},ensure_ascii=False))


if __name__=='__main__':
    main()
