#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Reads an Instruments export of the Animation Hitches table (xctrace export XML) and prints the hitch summary;
scripts/profile-scroll.sh runs it."""
import sys, xml.etree.ElementTree as ET
def rows(path):
    root = ET.parse(path).getroot()
    ids = {}
    def val(e):
        if e.get('ref'): return ids[e.get('ref')]
        v = (e.text or '', e.get('fmt') or '', e.tag)
        if e.get('id'): ids[e.get('id')] = v
        for c in e: val(c)
        return v
    out = []
    for r in root.iter('row'):
        out.append([val(c) for c in r])
    return out
base = sys.argv[1]
h = rows(f'{base}-hitches.xml')
fl = rows(f'{base}-hitches-frame-lifetimes.xml')
pest = [r for r in h if 'Pesto' in r[2][1]]
dur = [int(r[1][0]) / 1e6 for r in pest]
print('frames recorded (all procs):', len(fl))
print('pesto hitches:', len(pest), 'total ms %.0f' % sum(dur), 'worst %.0f ms' % (max(dur) if dur else 0))
durs = sorted(dur, reverse=True)
print('top hitches ms:', [round(x) for x in durs[:8]])
fd = [int(r[1][0]) / 1e6 for r in fl]
if fd:
    fd.sort()
    print('frame lifetime ms: median %.1f p95 %.1f max %.1f' % (fd[len(fd)//2], fd[int(len(fd)*.95)], fd[-1]))
