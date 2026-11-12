"""Shared Windows UI Automation helpers: selectors, element search, tree dump.

Selector syntax (parts joined with &&, scopes chained with >>):
    id:<AutomationId>        exact AutomationId (preferred)
    name:<Name>              exact Name
    name~:<text>             Name contains text
    role:<ControlType>       Button, Edit, CheckBox, Text, ListItem, Window, ... (no 'Control' suffix)
    class:<ClassName>        exact ClassName
    nth:<n>                  pick the n-th match (1-based); only together with other parts
Examples:
    id:SendButton
    role:Button && name:Send
    role:List && id:DeviceList >> role:ListItem && name~:Redmi
"""
import time

import uiautomation as auto

INTERACTIVE = {
    "ButtonControl", "SplitButtonControl", "EditControl", "CheckBoxControl", "RadioButtonControl",
    "ComboBoxControl", "ListItemControl", "MenuItemControl", "TabItemControl", "HyperlinkControl",
    "SliderControl", "SpinnerControl", "TreeItemControl", "DataItemControl", "DocumentControl",
    "ToggleButtonControl", "ScrollBarControl",
}
LABELS = {"TextControl", "HeaderItemControl", "ImageControl", "GroupControl", "ListControl",
          "TabControl", "MenuBarControl", "ToolBarControl", "WindowControl", "PaneControl", "CustomControl"}


class SelectorError(Exception):
    pass


def parse_part(text):
    """'role:Button && name:Send' -> dict of uiautomation search kwargs (+ nth)."""
    kw, nth = {}, 1
    for raw in text.split("&&"):
        raw = raw.strip()
        if not raw:
            continue
        if ":" not in raw:
            raise SelectorError("Bad selector part %r (expected key:value)" % raw)
        key, val = raw.split(":", 1)
        key, val = key.strip().lower(), val.strip()
        if key == "id":
            kw["AutomationId"] = val
        elif key == "name":
            kw["Name"] = val
        elif key == "name~":
            kw["SubName"] = val
        elif key == "role":
            ct = val if val.endswith("Control") else val + "Control"
            if not hasattr(auto.ControlType, ct):
                raise SelectorError("Unknown role %r" % val)
            kw["ControlType"] = getattr(auto.ControlType, ct)
        elif key == "class":
            kw["ClassName"] = val
        elif key == "nth":
            nth = int(val)
        else:
            raise SelectorError("Unknown selector key %r" % key)
    if not kw:
        raise SelectorError("Selector %r has no search criteria (nth alone is not allowed)" % text)
    return kw, nth


def parse(selector):
    return [parse_part(p) for p in selector.split(">>")]


def find(selector, root=None, timeout=10.0, depth=0xFFFFFFFF):
    """Wait up to `timeout` seconds for the selector; return the Control or None."""
    root = root or auto.GetRootControl()
    chain = parse(selector)
    deadline = time.time() + timeout
    while True:
        ctrl = root
        for kw, nth in chain:
            c = auto.Control(searchFromControl=ctrl, searchDepth=depth, foundIndex=nth, **kw)
            if not c.Exists(0, 0):
                ctrl = None
                break
            ctrl = c
        if ctrl is not None:
            # A generic Control has no Get*Pattern helpers; convert to the typed class (EditControl, ...).
            return auto.Control.CreateControlFromControl(ctrl) or ctrl
        if time.time() >= deadline:
            return None
        time.sleep(0.3)


def find_window(selector, timeout=10.0):
    """Top-level window: a selector, or plain text matched as a Name substring."""
    if ":" not in selector:
        selector = "name~:" + selector
    return find(selector, auto.GetRootControl(), timeout, depth=1)


def activate(c):
    """Bring the element's top-level window to the foreground (restore if minimized)."""
    try:
        top = c.GetTopLevelControl() or c
        hwnd = top.NativeWindowHandle
        if hwnd:
            if auto.IsIconic(hwnd):
                auto.ShowWindow(hwnd, auto.SW.Restore)
            auto.SetForegroundWindow(hwnd)
    except Exception:
        pass


def top_windows():
    out = []
    for w in auto.GetRootControl().GetChildren():
        if w.Name:
            out.append(w)
    return out


def suggest(c):
    role = c.ControlTypeName.replace("Control", "")
    if c.AutomationId and not c.AutomationId.isdigit():
        return "id:" + c.AutomationId
    if c.Name:
        name = c.Name.replace("&&", "").strip()
        first = name.replace("\r", "\n").split("\n")[0].strip()
        if first != name:  # multi-line Name (common in Flutter): match on the first line
            return "role:%s && name~:%s" % (role, first)
        return "role:%s && name:%s" % (role, name)
    return ""


def walk(root, max_depth=40):
    """Yield (control, depth) in tree order."""
    for c, d in auto.WalkControl(root, includeTop=True, maxDepth=max_depth):
        yield c, d


def clean(s):
    return (s or "").replace("\r", " ").replace("\n", " ").replace("|", "/").strip()


def dump_lines(root, show_all=False, max_depth=40):
    lines = ["AutomationId | Name | ControlType | enabled | selector"]
    n = 0
    anchors = []  # (depth, selector) of labelled ancestors, for scoping unnamed controls
    for c, d in walk(root, max_depth):
        try:
            ct = c.ControlTypeName
            aid, name = c.AutomationId, c.Name
            enabled = c.IsEnabled
        except Exception:  # element vanished mid-walk
            continue
        while anchors and anchors[-1][0] >= d:
            anchors.pop()
        interactive = ct in INTERACTIVE
        labelled = bool(name or aid)
        sel = suggest(c)
        if not labelled and interactive and anchors:
            # e.g. an unnamed toggle inside a named row (Flutter): scope it under the row
            sel = "%s >> role:%s" % (anchors[-1][1], ct.replace("Control", ""))
        if labelled and sel and d > 0:
            anchors.append((d, sel))
        if not show_all:
            if not labelled and not (interactive and anchors):
                continue
            if not interactive and ct not in LABELS:
                continue
        extra = ""
        if ct in ("CheckBoxControl", "ToggleButtonControl"):
            try:
                extra = ",on" if c.GetTogglePattern().ToggleState == 1 else ",off"
            except Exception:
                pass
        lines.append("%s%s | %s | %s | %s | %s" % (
            "  " * min(d, 12), clean(aid), clean(name), ct.replace("Control", ""),
            ("yes" if enabled else "no") + extra, sel))
        n += 1
    lines.append("-- %d elements" % n)
    return lines
