#!/usr/bin/env python3
"""Drive quickgui via AT-SPI while Orca runs: activates each nav
destination with its 'Tap' action, then 'Focus', logging state changes
(the events Orca turns into speech).

Usage: PYTHONPATH=<pyatspi> python3 tool/orca_drive.py
"""
import sys
import time

import pyatspi  # noqa: E402

NAV = ("Inicio", "Máquinas", "Crear", "Automatización",
       "Actividad", "Diagnóstico", "Ajustes",
       "Home", "Machines", "Create", "Automation",
       "Activity", "Diagnostics", "Settings")


def walk(node, depth, out):
    if depth > 14 or node is None:
        return
    out.append(node)
    try:
        n = node.childCount
    except Exception:
        n = 0
    for i in range(min(n, 40)):
        try:
            walk(node.getChildAtIndex(i), depth + 1, out)
        except Exception:
            pass


def find_app():
    desktop = pyatspi.Registry.getDesktop(0)
    for i in range(desktop.childCount):
        a = desktop.getChildAtIndex(i)
        if a is not None and "quickgui" in (a.name or "").lower():
            return a
    return None


def do(node, *wanted):
    try:
        ai = node.queryAction()
    except Exception:
        return None
    names = [ai.getName(i) for i in range(ai.nActions)]
    for w in wanted:
        if w in names:
            ai.doAction(names.index(w))
            return w
    return None


def main():
    app = None
    for _ in range(40):
        app = find_app()
        if app is not None:
            break
        time.sleep(0.5)
    if app is None:
        print("FAIL: quickgui not on AT-SPI bus")
        sys.exit(1)

    nodes = []
    walk(app, 0, nodes)
    nav = [n for n in nodes
           if (n.name or "").split("\n", 1)[0].strip() in NAV
           and "\n" in (n.name or "")]
    print("nav nodes: %d" % len(nav))

    for n in nav:
        label = (n.name or "").split("\n")[0]
        acted = do(n, "Tap", "press", "activate", "click")
        print("tap %-15r -> %s" % (label, acted))
        time.sleep(1.0)
        try:
            print("    frame title: %r" % app.getChildAtIndex(0).name)
        except Exception:
            pass
        time.sleep(0.5)


if __name__ == "__main__":
    main()
