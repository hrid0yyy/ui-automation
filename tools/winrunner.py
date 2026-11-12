"""Run a Windows workflow YAML step by step and log every step.

Usage:
  python winrunner.py <workflow.yml> --out <dir> [--env KEY=VALUE ...] [--validate]

Writes <dir>/steps.json: {"result": "passed|failed", "steps": [...]}.
On a failing step it saves step<N>.png (screen) and step<N>.txt (window tree).

Workflow format (see AGENTS.md for the full list of actions):

  testCaseId: WTC-101
  name: Quick Share opens
  app: quick-share
  minVersion: "1.0.0"
  maxVersion: ""
  tags: [smoke]
  settings: [bluetooth:on]
  window: "name:Quick Share"        # default scope for selectors
  steps:
    - launch: {aumid: "NearbyShare_21hpf16v5xp10!NearbyShare"}
    - id: wait_home
      wait: "role:Text && name~:Ready to receive"
      timeout: 20
    - click: "role:Button && name:Select files"
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

import uiautomation as auto
import yaml

import wincore

ACTIONS = {"launch", "close", "window", "click", "double_click", "right_click", "invoke", "type",
           "key", "wait", "wait_gone", "assert", "assert_not", "toggle", "select", "scroll_into_view",
           "screenshot", "run_flow", "pause"}
STEP_KEYS = {"id", "timeout", "optional", "description", "window"}
DEFAULT_TIMEOUT = 10.0


class StepFailed(Exception):
    pass


def subst(value, env):
    """Replace ${VAR} in strings (recursively), like Maestro."""
    if isinstance(value, str):
        def rep(m):
            k = m.group(1)
            if k not in env:
                raise StepFailed("Variable ${%s} is not set" % k)
            return str(env[k])
        return re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", rep, value)
    if isinstance(value, list):
        return [subst(v, env) for v in value]
    if isinstance(value, dict):
        return {k: subst(v, env) for k, v in value.items()}
    return value


def load_workflow(path):
    with open(path, "r", encoding="utf-8") as f:
        wf = yaml.safe_load(f) or {}
    if not isinstance(wf.get("steps"), list):
        raise SystemExit("%s: 'steps' list missing" % path)
    for i, s in enumerate(wf["steps"], 1):
        if not isinstance(s, dict):
            raise SystemExit("%s step %d: must be a mapping" % (path, i))
        acts = [k for k in s if k not in STEP_KEYS]
        if len(acts) != 1 or acts[0] not in ACTIONS:
            raise SystemExit("%s step %d: needs exactly one action from %s, got %s"
                             % (path, i, sorted(ACTIONS), acts))
    return wf


def step_name(action, arg):
    if isinstance(arg, dict):
        arg = arg.get("selector") or arg.get("aumid") or arg.get("exe") or arg.get("path") or \
            arg.get("process") or arg.get("keys") or ", ".join("%s=%s" % kv for kv in arg.items())
    return ("%s %s" % (action, arg if arg is not None else "")).strip()


class Runner:
    def __init__(self, out_dir, env):
        self.out = out_dir
        self.env = env
        self.steps = []
        self.n = 0
        self.scope_sel = None  # current window selector

    # -- helpers -------------------------------------------------------------
    def scope(self, timeout):
        if not self.scope_sel:
            return auto.GetRootControl()
        w = wincore.find_window(self.scope_sel, timeout)
        if w is None:
            raise StepFailed("Window not found: %s" % self.scope_sel)
        return w

    def element(self, selector, timeout):
        root = self.scope(timeout)
        c = wincore.find(selector, root, timeout)
        if c is None:
            raise StepFailed("Element not found: %s" % selector)
        return c

    def focus_window(self, c):
        wincore.activate(c)

    def capture(self, n):
        shot, tree = "step%d.png" % n, "step%d.txt" % n
        try:
            auto.GetRootControl().CaptureToImage(os.path.join(self.out, shot))
        except Exception:
            shot = None
        try:
            root = self.scope(1) if self.scope_sel else auto.GetForegroundControl().GetTopLevelControl()
            with open(os.path.join(self.out, tree), "w", encoding="utf-8") as f:
                f.write("\n".join(wincore.dump_lines(root, show_all=True)))
        except Exception as e:
            with open(os.path.join(self.out, tree), "w", encoding="utf-8") as f:
                f.write("tree unavailable: %s" % e)
        return shot, tree

    # -- actions ---------------------------------------------------------------
    def do(self, action, arg, t, base_dir):
        sel = arg.get("selector") if isinstance(arg, dict) else arg
        if action == "launch":
            if arg.get("aumid"):
                subprocess.Popen(["explorer.exe", "shell:AppsFolder\\" + arg["aumid"]])
            elif arg.get("exe"):
                subprocess.Popen([arg["exe"]] + list(arg.get("args", [])))
            else:
                raise StepFailed("launch needs aumid or exe")
            if arg.get("window"):
                self.scope_sel = arg["window"]
            if self.scope_sel:
                wincore.activate(self.scope(t))
        elif action == "close":
            name = arg["process"] if isinstance(arg, dict) else arg
            subprocess.run(["taskkill", "/IM", name, "/F"], capture_output=True)
            end = time.time() + t
            while time.time() < end:
                r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq %s" % name], capture_output=True, text=True)
                if name.lower() not in r.stdout.lower():
                    return
                time.sleep(0.3)
            raise StepFailed("Process still running: %s" % name)
        elif action == "window":
            self.scope_sel = arg
            wincore.activate(self.scope(t))
        elif action in ("click", "double_click", "right_click"):
            c = self.element(sel, t)
            self.focus_window(c)
            if action == "click":
                c.Click(simulateMove=False, waitTime=0.2)
            elif action == "double_click":
                c.DoubleClick(simulateMove=False, waitTime=0.2)
            else:
                c.RightClick(simulateMove=False, waitTime=0.2)
        elif action == "invoke":
            c = self.element(sel, t)
            c.GetInvokePattern().Invoke()
        elif action == "type":
            c = self.element(arg["selector"], t)
            text = str(arg.get("text", ""))
            try:
                vp = c.GetValuePattern()
                if arg.get("clear", True):
                    vp.SetValue("")
                vp.SetValue(text if arg.get("clear", True) else (vp.Value or "") + text)
            except Exception:
                self.focus_window(c)
                c.Click(simulateMove=False)
                if arg.get("clear", True):
                    auto.SendKeys("{Ctrl}a{Del}", waitTime=0.1)
                auto.SendKeys(text, interval=0.01, waitTime=0.1, charMode=True)
        elif action == "key":
            if self.scope_sel:
                wincore.activate(self.scope(t))
            auto.SendKeys(arg, waitTime=0.2)
        elif action == "wait":
            self.element(sel, t)
        elif action == "wait_gone":
            root = self.scope(t)
            end = time.time() + t
            while time.time() < end:
                if wincore.find(sel, root, 0) is None:
                    return
                time.sleep(0.3)
            raise StepFailed("Still visible: %s" % sel)
        elif action == "assert":
            c = self.element(sel, t)
            if isinstance(arg, dict):
                if "name" in arg and c.Name != arg["name"]:
                    raise StepFailed("Name is %r, expected %r" % (c.Name, arg["name"]))
                if "value" in arg:
                    v = c.GetValuePattern().Value
                    if v != arg["value"]:
                        raise StepFailed("Value is %r, expected %r" % (v, arg["value"]))
                if "enabled" in arg and bool(c.IsEnabled) != bool(arg["enabled"]):
                    raise StepFailed("Enabled is %s, expected %s" % (c.IsEnabled, arg["enabled"]))
                if "toggled" in arg:
                    on = c.GetTogglePattern().ToggleState == 1
                    if on != bool(arg["toggled"]):
                        raise StepFailed("Toggle is %s, expected %s" % (on, arg["toggled"]))
        elif action == "assert_not":
            root = self.scope(t)
            if wincore.find(sel, root, 0) is not None:
                raise StepFailed("Unexpectedly present: %s" % sel)
        elif action == "toggle":
            c = self.element(arg["selector"], t)
            tp = c.GetTogglePattern()
            want = bool(arg.get("on", True))
            for _ in range(3):
                if (tp.ToggleState == 1) == want:
                    return
                tp.Toggle()
                time.sleep(0.2)
            raise StepFailed("Could not set toggle to %s" % want)
        elif action == "select":
            c = self.element(sel, t)
            c.GetSelectionItemPattern().Select()
        elif action == "scroll_into_view":
            c = self.element(sel, t)
            c.GetScrollItemPattern().ScrollIntoView()
        elif action == "screenshot":
            name = arg if isinstance(arg, str) else "screen"
            auto.GetRootControl().CaptureToImage(os.path.join(self.out, name + ".png"))
        elif action == "pause":
            # Only for runner self-tests; AGENTS.md forbids fixed sleeps in test cases.
            time.sleep(float(arg))
        elif action == "run_flow":
            path = arg["path"] if isinstance(arg, dict) else arg
            path = os.path.normpath(os.path.join(base_dir, path))
            saved = dict(self.env)
            if isinstance(arg, dict):
                self.env.update({k: str(v) for k, v in (arg.get("env") or {}).items()})
            sub = load_workflow(path)
            ok = self.run_steps(sub, os.path.dirname(path), prefix=os.path.basename(path) + ": ")
            self.env = saved
            if not ok:
                raise StepFailed("Subflow failed: %s" % os.path.basename(path))
        else:
            raise StepFailed("Unknown action %s" % action)

    def run_steps(self, wf, base_dir, prefix=""):
        if wf.get("window") and not prefix:
            self.scope_sel = subst(wf["window"], self.env)
        for raw in wf["steps"]:
            action = next(k for k in raw if k not in STEP_KEYS)
            self.n += 1
            n = self.n
            rec = {"n": n, "id": raw.get("id"), "name": prefix + step_name(action, raw[action]), "status": "running"}
            self.steps.append(rec)
            start = time.time()
            saved_scope = self.scope_sel
            try:
                arg = subst(raw[action], self.env)
                rec["name"] = prefix + step_name(action, arg)
                if raw.get("window"):
                    self.scope_sel = subst(raw["window"], self.env)
                t = float(raw.get("timeout", DEFAULT_TIMEOUT))
                self.do(action, arg, t, base_dir)
                rec["status"] = "passed"
            except Exception as e:
                msg = str(e) or e.__class__.__name__
                if raw.get("optional"):
                    rec["status"] = "skipped"
                    rec["error"] = msg
                else:
                    rec["status"] = "failed"
                    rec["error"] = msg
                    if action != "run_flow":
                        rec["screenshot"], rec["tree"] = self.capture(n)
            finally:
                if raw.get("window"):
                    self.scope_sel = saved_scope
                rec["duration_ms"] = int((time.time() - start) * 1000)
                print("[%s] %d %s (%d ms)%s" % (rec["status"].upper(), n, rec["name"], rec["duration_ms"],
                                                 (" - " + rec["error"]) if rec.get("error") else ""), flush=True)
            if rec["status"] == "failed":
                return False
        return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("workflow")
    ap.add_argument("--out", required=False)
    ap.add_argument("--env", action="append", default=[], help="KEY=VALUE")
    ap.add_argument("--validate", action="store_true", help="only check the YAML structure")
    a = ap.parse_args()

    wf = load_workflow(a.workflow)
    if a.validate:
        print("OK: %d steps" % len(wf["steps"]))
        return 0
    if not a.out:
        raise SystemExit("--out is required")
    os.makedirs(a.out, exist_ok=True)
    env = {k: str(v) for k, v in (wf.get("env") or {}).items()}
    for kv in a.env:
        k, _, v = kv.partition("=")
        env[k] = v

    r = Runner(a.out, env)
    ok = r.run_steps(wf, os.path.dirname(os.path.abspath(a.workflow)))
    with open(os.path.join(a.out, "steps.json"), "w", encoding="utf-8") as f:
        json.dump({"result": "passed" if ok else "failed", "steps": r.steps}, f, indent=2)
    return 0 if ok else 1


if __name__ == "__main__":
    auto.SetGlobalSearchTimeout(1)
    sys.exit(main())
