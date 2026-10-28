#!/usr/bin/env python3
import os, re, sys

TDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "translations")

def entries(fn):
    """Return dict msgid -> msgstr (both unquoted, joined multi-line)."""
    text = open(fn, encoding="utf-8").read()
    out = {}
    # Match msgid ... msgstr pairs; msgid may span multiple "..." lines.
    for m in re.finditer(
        r'msgid\s+((?:"(?:[^"\\]|\\.)*"\s*)+)\s*msgstr\s+((?:"(?:[^"\\]|\\.)*"\s*)*)',
        text):
        mid = "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)))
        mst = "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2)))
        out[mid] = mst
    return out

pot_ids = set(entries(os.path.join(TDIR, "quickgui.pot")).keys())
pot_ids.discard("")
total = len(pot_ids)
print("POT msgids:", total)
for f in sorted(os.listdir(TDIR)):
    if not f.endswith(".po"):
        continue
    e = entries(os.path.join(TDIR, f))
    done = sum(1 for k in pot_ids if e.get(k, ""))
    missing = [k for k in pot_ids if not e.get(k, "")]
    print("%-10s %3d/%d" % (f, done, total))
    if f in ("en.po", "es.po") and missing:
        for k in missing[:30]:
            print("   missing:", k[:90])
