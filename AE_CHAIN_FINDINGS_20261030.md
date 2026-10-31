# Exposure chain findings

> **历史记录，不作为当前版本操作说明**：本文保留当时实验、测量及计划；其中“当前/已烧录/下一步”、算法开关、资源和本机路径仅适用于文内历史版本。当前五拨码最终版以[README](README.md)及[算法说明](CURRENT_ALGORITHMS.md)为准。


Current branch stage1. Real HDMI samples: face ROI (x500:1400,y200:950) RGB means: orig1 [65.5,62.3,63.4], orig2 [61.6,58.5,59.6], orig3 [56.2,53.8,55.1]. Ratios stable; issue is luminance from exposure, not AWB hue.

Current chain: ae_set.v r_ae_set 1600/1200/900, r_ag=160 -> sensor exposure; isp_top axis_gamma_rgb96 after vendor awb; design_top SHADING_ON, AWB_SIMPLE off. Vendor AWB preserves chroma. color_shading modifies only R/B, G pass-through.

Critical gamma bug: isp_top gamma07 case 4'hf default base=255 delta=0. Mapping x=239 ->243, x=240..254 ->255, a 16-code jump; high highlights clip prematurely. Change F segment to smooth base=244 delta=11 (or equivalent knee) and keep x=255=255. This is low resource, no extra DSP/ERAM.

Recommended sequence: (1) correct gamma F segment and compile/test at exposure 1600; (2) if face still dark, use exposure ~1700-1800 (between orig0=1991 and orig1=1600) with corrected high knee; (3) if still mixed scene issue, add frame-level low-rate AE based on weighted midtone/skin ROI and highlight saturation with hysteresis, sensor exposure control only. A single fixed exposure cannot retain window details and face simultaneously; local tone curve can lift shadows/midtones but cannot recover sensor-clipped pixels.

Do not first increase AWB gains or color shading: those alter color (R/B only) and cannot fix luminance. Existing gamma raises shadows x^0.7 but F segment crushes highlights.
