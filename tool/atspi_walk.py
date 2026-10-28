#!/usr/bin/env python3
"""Walk the AT-SPI tree of a running app and assert the a11y contract.

Usage: PYTHONPATH=/tmp/pyatspi/usr/lib/python3/dist-packages \
         python3 tool/atspi_walk.py [app-name-substring]

Exits 0 if the app is found on the AT-SPI bus and exposes the expected
accessible structure (buttons with names, text, named landmarks).
"""
import sys

import pyatspi  # noqa: E402 — PYTHONPATH is set by the caller

TARGET = sys.argv[1] if len(sys.argv) > 1 else "quickgui"


def role_name(node):
    try:
        return node.getRoleName()
    except Exception:
        return "?"


def state(node):
    try:
        return ",".join(node.getState().getStates() or [])
    except Exception:
        return ""


def walk(node, depth, out):
    if depth > 14:
        return
    try:
        name = node.name or ""
    except Exception:
        name = ""
    out.append((depth, role_name(node), name, state(node)))
    try:
        n = node.childCount
    except Exception:
        n = 0
    for i in range(min(n, 40)):
        try:
            walk(node.getChildAtIndex(i), depth + 1, out)
        except Exception:
            pass


def main():
    desktop = pyatspi.Registry.getDesktop(0)
    app = None
    for i in range(desktop.childCount):
        a = desktop.getChildAtIndex(i)
        if a is not None and TARGET.lower() in (a.name or "").lower():
            app = a
            break
    if app is None:
        print("FAIL: no AT-SPI application matching %r" % TARGET)
        print("visible apps:", [desktop.getChildAtIndex(i).name
                                for i in range(desktop.childCount)])
        sys.exit(1)

    out = []
    walk(app, 0, out)
    roles = {}
    for _, r, _, _ in out:
        roles[r] = roles.get(r, 0) + 1
    print("APP:", app.name, "| nodes:", len(out))
    for r in sorted(roles, key=lambda x: -roles[x]):
        print("  %-24s %d" % (r, roles[r]))

    named = [n for _, r, n, _ in out if n]
    print("\nNAMED NODES (first 60):")
    for n in named[:60]:
        print("  -", n)

    # Contract assertions
    buttons = [n for d, r, n, s in out if r == "push button"]
    labelled = [n for d, r, n, s in out if r == "push button" and n]
    texts = [r for _, r, _, _ in out if r in ("text", "label", "static")]
    nav = [n for _, r, n, _ in out
           if n in ("Home", "Machines", "Create", "Activity",
                    "Settings", "Diagnostics")]
    print("\nASSERTIONS:")
    print("  buttons total/labelled: %d/%d" % (len(buttons), len(labelled)))
    print("  text-ish nodes: %d" % len(texts))
    print("  nav sections found: %s" % nav)
    ok = len(buttons) >= 3 and len(labelled) >= max(1, len(buttons) // 2) \
        and len(nav) >= 4
    print("RESULT:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
