"""Print a Windows app window as a compact element list.

Usage:
  python winexplore.py                      list top-level windows
  python winexplore.py --window "Quick Share" [--all] [--depth N] [--screenshot out.png]
"""
import argparse
import sys
import time

import uiautomation as auto

import wincore


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--window", help="window Name substring, or a selector like 'id:...'")
    ap.add_argument("--all", action="store_true", help="include unlabelled / non-interactive elements")
    ap.add_argument("--depth", type=int, default=40)
    ap.add_argument("--screenshot")
    a = ap.parse_args()

    if not a.window:
        fg = auto.GetForegroundControl()
        fg_top = fg.GetTopLevelControl() if fg else None
        print("Top-level windows (pass one with -Window):")
        for w in wincore.top_windows():
            mark = "*" if fg_top and w.NativeWindowHandle == fg_top.NativeWindowHandle else " "
            print(" %s %s | %s | pid %s" % (mark, wincore.clean(w.Name), w.ControlTypeName.replace("Control", ""), w.ProcessId))
        return 0

    win = wincore.find_window(a.window, timeout=5)
    if win is None:
        print("Window not found: %s" % a.window, file=sys.stderr)
        return 2
    print("window: %s | pid %s | class %s" % (wincore.clean(win.Name), win.ProcessId, win.ClassName))
    lines = wincore.dump_lines(win, a.all, a.depth)
    if len(lines) <= 10:
        # Flutter / some WinUI apps build their accessibility tree only after the first
        # UI Automation query; give it a moment and read again.
        time.sleep(1.5)
        lines = wincore.dump_lines(win, a.all, a.depth)
    for line in lines:
        print(line)
    if a.screenshot:
        win.CaptureToImage(a.screenshot)
        print("screenshot: " + a.screenshot)
    return 0


if __name__ == "__main__":
    sys.exit(main())
