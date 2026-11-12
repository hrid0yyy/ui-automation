"""Helpers for run.ps1 (prints JSON on stdout).

  python testmeta.py meta <test-file>             test-case header, both platforms
  python testmeta.py maestro-steps <debug-dir>    per-step list from Maestro's commands-*.json
  python testmeta.py in-range <ver> <min> <max>   prints true/false
"""
import glob
import json
import os
import re
import sys

import yaml


def as_list(v):
    if v is None or v == "":
        return []
    if isinstance(v, list):
        return [str(x).strip() for x in v if str(x).strip()]
    return [x.strip() for x in str(v).split(",") if x.strip()]


def meta(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    is_android = os.sep + "android" + os.sep in os.path.abspath(path) or "\n---" in text
    if is_android:
        head = yaml.safe_load(text.split("\n---", 1)[0]) or {}
        props = head.get("properties") or {}
        return {
            "platform": "android",
            "testCaseId": props.get("testCaseId") or "",
            "name": head.get("name") or "",
            "app": props.get("app") or "",
            "appId": head.get("appId") or "",
            "minVersion": str(props.get("minVersion") or ""),
            "maxVersion": str(props.get("maxVersion") or ""),
            "tags": as_list(head.get("tags")),
            "settings": as_list(props.get("settings")),
            "launchIntent": str(props.get("launchIntent") or ""),
            "pairedWith": str(props.get("pairedWith") or ""),
            "pairedFrom": str(props.get("pairedFrom") or ""),
            "fixture": str(props.get("fixture") or ""),
        }
    wf = yaml.safe_load(text) or {}
    return {
        "platform": "windows",
        "testCaseId": wf.get("testCaseId") or "",
        "name": wf.get("name") or "",
        "app": wf.get("app") or "",
        "minVersion": str(wf.get("minVersion") or ""),
        "maxVersion": str(wf.get("maxVersion") or ""),
        "tags": as_list(wf.get("tags")),
        "settings": as_list(wf.get("settings")),
        "pairedWith": str(wf.get("pairedWith") or ""),
        "fixture": str(wf.get("fixture") or ""),
    }


def vparts(v):
    m = re.match(r"\s*(\d+(?:\.\d+)*)", v or "")
    return [int(x) for x in m.group(1).split(".")] if m else None


def cmp(a, b):
    n = max(len(a), len(b))
    a, b = a + [0] * (n - len(a)), b + [0] * (n - len(b))
    return (a > b) - (a < b)


def in_range(ver, lo, hi):
    v = vparts(ver)
    if v is None:
        return False
    if lo and vparts(lo) and cmp(v, vparts(lo)) < 0:
        return False
    if hi and vparts(hi) and cmp(v, vparts(hi)) > 0:
        return False
    return True


def describe(cmd):
    """{'tapOnElement': {'selector': {'idRegex': 'x'}}} -> 'tapOnElement id=x'"""
    if not isinstance(cmd, dict) or not cmd:
        return str(cmd)
    name, body = next(((k, v) for k, v in cmd.items() if v is not None), (None, None))
    if name is None:
        return "?"
    label = name.replace("Command", "")
    if isinstance(body, dict):
        if body.get("label"):
            return "%s %s" % (label, body["label"])
        cond = body.get("condition") or {}
        for kind in ("visible", "notVisible"):
            if isinstance(cond.get(kind), dict):
                body = dict(body, selector=cond[kind])
                label = "assertVisible" if kind == "visible" else "assertNotVisible"
        sel = body.get("selector") or {}
        bits = []
        for k, short in (("idRegex", "id"), ("textRegex", "text")):
            if sel.get(k):
                bits.append("%s=%s" % (short, sel[k]))
        for k in ("text", "appId", "sourceDescription", "direction", "link", "key"):
            if body.get(k) and not isinstance(body.get(k), (dict, list)):
                bits.append("%s=%s" % (k, body[k]))
        if bits:
            return "%s %s" % (label, " ".join(bits))
    return label


SKIP = {"defineVariablesCommand", "applyConfigurationCommand"}


def maestro_steps(debug_dir):
    files = sorted(glob.glob(os.path.join(debug_dir, "**", "commands*.json"), recursive=True),
                   key=os.path.getmtime)
    steps = []
    for f in files:
        with open(f, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        for entry in data:
            md = entry.get("metadata") or {}
            cmd = md.get("evaluatedCommand") or entry.get("command") or {}
            if next(iter(cmd), "") in SKIP:
                continue
            status = (md.get("status") or "").upper()
            st = {"COMPLETED": "passed", "FAILED": "failed", "SKIPPED": "skipped", "WARNED": "passed"}.get(status, status.lower() or "unknown")
            step = {"n": len(steps) + 1, "name": "  " * int(md.get("depth") or 0) + describe(cmd), "status": st,
                    "duration_ms": int(md.get("duration") or 0)}
            err = md.get("error")
            if err:
                step["error"] = err.get("message") if isinstance(err, dict) else str(err)
            steps.append(step)
    return steps


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    cmd = sys.argv[1]
    if cmd == "meta":
        out = meta(sys.argv[2])
    elif cmd == "maestro-steps":
        out = maestro_steps(sys.argv[2])
    elif cmd == "in-range":
        lo = sys.argv[3] if len(sys.argv) > 3 else ""
        hi = sys.argv[4] if len(sys.argv) > 4 else ""
        out = in_range(sys.argv[2], lo, hi)
    else:
        raise SystemExit(__doc__)
    print(json.dumps(out))


if __name__ == "__main__":
    main()
