#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Validate EVERY instantiation in design_top_wrapper.v against the real module
definitions: named parameters must exist, named ports must exist.

This is the check that would have caught `.PX_PER_BEAT(4)` being left behind.
"""
import io, os, re, sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOP  = os.path.join(PROJ, "user_source", "hdl_source", "design_top_wrapper.v")
AL   = os.path.join(PROJ, "td_project", "camera_to_dsi_display.al")


def rd(p):
    return io.open(p, "rb").read().decode("utf-8", "replace")


def nocmt(t):
    t = re.sub(r"/\*.*?\*/", " ", t, flags=re.S)
    return re.sub(r"//[^\n]*", " ", t)


def parse_module(text, name):
    """Return (params, ports) for `module <name>`."""
    m = re.search(r"\bmodule\s+%s\b" % re.escape(name), text)
    if not m:
        return None, None
    rest = text[m.end():]
    params, ports = [], []
    # optional parameter block
    pm = re.match(r"\s*#\s*\(", rest)
    if pm:
        depth, i = 1, pm.end()
        while i < len(rest) and depth:
            if rest[i] == "(":
                depth += 1
            elif rest[i] == ")":
                depth -= 1
            i += 1
        pblock = rest[pm.end():i - 1]
        params = re.findall(r"\bparameter\b[^,]*?\b(\w+)\s*=", pblock)
        rest = rest[i:]
    # port list: up to the first ';'
    j = rest.find(";")
    if j >= 0:
        pblock = rest[:j]
        pblock = re.sub(r"\b(input|output|inout)\b", "|", pblock)
        pblock = pblock.replace("(", " ").replace(")", " ")
        # Strip type keywords, not substrings in names such as O_region_sel.
        pblock = re.sub(r"\b(?:wire|reg|signed)\b", " ", pblock)
        pblock = re.sub(r"\[[^\]]*\]", " ", pblock)
        for chunk in pblock.split("|")[1:]:
            for nm in chunk.split(","):
                nm = nm.strip()
                if re.fullmatch(r"[A-Za-z_]\w*", nm):
                    ports.append(nm)
    return params, ports


def main():
    al = rd(AL)
    al_dir = os.path.dirname(AL)
    # module table from every verilog file in the project
    mods = {}
    files = []
    # 额外文件：用 `include 拉进来的（不在 .al 里，TD 看不到但会被编译）
    extra = [os.path.join(PROJ, "user_source", "hdl_source", "vib_prev_frame_ddr.v"),
             os.path.join(PROJ, "user_source", "hdl_source", "vib_gauss3x3.v"),
             os.path.join(PROJ, "user_source", "hdl_source", "vib_lk_grid.v"),
             os.path.join(PROJ, "user_source", "hdl_source", "highlight_region.v")]
    # Included multi-block modules are not separate .al sources. Check their
    # real interfaces too, rather than silently skipping the newly active chain.
    extra.extend(os.path.join(PROJ, "user_source", "hdl_source", "vibration", name)
                 for name in ("vib_lk_grid_multi.v", "vib_eram_dp.v",
                              "vib_gz_multi.v", "vib_gz_peak.v",
                              "vib_osd_marker.v", "vib_goertzel.v"))
    for full in extra:
        if os.path.isfile(full):
            files.append(full)
            t = nocmt(rd(full))
            for nm in re.findall(r"^\s*module\s+(\w+)", t, re.M):
                p, po = parse_module(t, nm)
                mods[nm] = (p or [], po or [], full)
    for rel in re.findall(r'<File Path="([^"]+)"', al):
        full = os.path.normpath(os.path.join(al_dir, rel))
        if not os.path.isfile(full) or not full.lower().endswith((".v", ".sv")):
            continue
        files.append(full)
        t = nocmt(rd(full))
        for nm in re.findall(r"^\s*module\s+(\w+)", t, re.M):
            p, po = parse_module(t, nm)
            mods[nm] = (p or [], po or [], full)
    print("扫描 %d 个文件, 共 %d 个模块定义" % (len(files), len(mods)))

    top = rd(TOP)
    topl = nocmt(top)
    print("检查 %s 里所有例化 ..." % os.path.basename(TOP))

    rc = 0
    checked = 0
    for name, (params, ports, src) in sorted(mods.items()):
        # find instantiations of `name`
        for im in re.finditer(
                r"\b%s\b\s*(#\s*\()?" % re.escape(name), topl):
            start = im.end()
            has_par = bool(im.group(1))
            pnames = []
            if has_par:
                depth, i = 1, start
                while i < len(topl) and depth:
                    if topl[i] == "(":
                        depth += 1
                    elif topl[i] == ")":
                        depth -= 1
                    i += 1
                pblk = topl[start:i - 1]
                pnames = re.findall(r"\.(\w+)\s*\(", pblk)
                start = i
            # instance name then port list
            nm = re.match(r"\s*(\w+)\s*\(", topl[start:])
            if not nm:
                continue
            i = start + nm.end()
            depth = 1
            j = i
            while j < len(topl) and depth:
                if topl[j] == "(":
                    depth += 1
                elif topl[j] == ")":
                    depth -= 1
                j += 1
            pblk = topl[i:j - 1]
            cnames = re.findall(r"\.(\w+)\s*\(", pblk)
            if not cnames:
                continue
            checked += 1
            bad_p = [p for p in pnames if p not in params]
            bad_c = [c for c in cnames if c not in ports]
            if bad_p or bad_c:
                rc = 1
                print("  FAIL %s (实例 %s, 定义在 %s)" % (name, nm.group(1), os.path.basename(src)))
                if bad_p:
                    print("        参数不存在: %s   (模块参数: %s)" % (bad_p, params))
                if bad_c:
                    print("        端口不存在: %s" % bad_c)
            else:
                print("  OK   %-32s 实例=%-26s 参数=%d 端口=%d"
                      % (name, nm.group(1), len(pnames), len(cnames)))
    print()
    print("共校验 %d 个例化 -> %s" % (checked, "全部通过" if rc == 0 else "有问题"))
    return rc


if __name__ == "__main__":
    sys.exit(main())
