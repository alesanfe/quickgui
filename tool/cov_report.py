#!/usr/bin/env python3
import os

ROOT = os.path.dirname(os.path.abspath(__file__)) + os.sep + ".."
LCOV = os.path.join(ROOT, "coverage", "lcov.info")
PFX = os.path.abspath(ROOT) + os.sep

lf, lh, cur = {}, {}, None
for l in open(LCOV):
    if l.startswith("SF:"):
        cur = l[3:].strip()
    elif l.startswith("LF:"):
        lf[cur] = int(l[3:])
    elif l.startswith("LH:"):
        lh[cur] = int(l[3:])

rows = [(f, lh.get(f, 0), lf[f]) for f in lf if lf[f] >= 30]
rows.sort(key=lambda r: r[1] / r[2])
for f, c, t in rows[:25]:
    print("%5.1f%%  %4d/%4d  %s" % (100 * c / t, c, t, f.replace(PFX, "")))
print("---")
tot = sum(lf.values())
cov = sum(lh.get(f, 0) for f in lf)
print("TOTAL %d/%d = %.1f%%" % (cov, tot, 100 * cov / tot))
