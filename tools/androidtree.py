"""Compact an Android view hierarchy into one line per useful element.

Input: a `maestro hierarchy` JSON dump or an `adb shell uiautomator dump` XML file.
Output: id | text | desc | class | clickable | bounds | suggested Maestro selector

Usage: python androidtree.py <dump-file> [--all]
"""
import json
import sys
import xml.etree.ElementTree as ET

INPUTS = {"EditText", "Switch", "CheckBox", "RadioButton", "SeekBar", "Spinner", "Button",
          "ImageButton", "ToggleButton", "CompoundButton", "AutoCompleteTextView"}


def norm(node):
    """Return a flat dict for one node from either format."""
    a = node
    return {
        "id": a.get("resource-id", "") or "",
        "text": a.get("text", "") or "",
        "desc": a.get("content-desc", "") or a.get("accessibilityText", "") or "",
        "hint": a.get("hintText", "") or "",
        "cls": (a.get("class", "") or "").rsplit(".", 1)[-1],
        "clickable": str(a.get("clickable", "")).lower() == "true",
        "enabled": str(a.get("enabled", "true")).lower() != "false",
        "checked": str(a.get("checked", "")).lower() == "true",
        "bounds": a.get("bounds", "") or "",
    }


def walk_json(node, out):
    attrs = node.get("attributes") or {}
    if attrs:
        out.append(norm(attrs))
    for ch in node.get("children") or []:
        walk_json(ch, out)


def walk_xml(el, out):
    if el.tag == "node":
        out.append(norm(el.attrib))
    for ch in el:
        walk_xml(ch, out)


def load(path):
    raw = open(path, "rb").read().decode("utf-8", "replace")
    start = min([i for i in (raw.find("{"), raw.find("<")) if i >= 0], default=-1)
    if start < 0:
        raise SystemExit("No hierarchy found in dump:\n" + raw[:500])
    raw = raw[start:]
    out = []
    if raw.startswith("{"):
        end = raw.rfind("}")
        walk_json(json.loads(raw[: end + 1]), out)
    else:
        end = raw.rfind(">")
        walk_xml(ET.fromstring(raw[: end + 1]), out)
    return out


def selector(e, id_counts):
    if e["id"] and id_counts.get(e["id"], 0) == 1:
        return "id: " + e["id"]
    if e["id"] and e["text"]:
        return '{id: "%s", text: "%s"}' % (e["id"], e["text"])
    if e["text"]:
        return "text: " + e["text"]
    if e["desc"]:
        return "text: " + e["desc"]  # Maestro text matching also checks accessibility text
    return ""


def clean(s):
    return s.replace("\n", " ").replace("|", "/").strip()


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    show_all = "--all" in sys.argv
    nodes = load(sys.argv[1])
    id_counts = {}
    for e in nodes:
        if e["id"]:
            id_counts[e["id"]] = id_counts.get(e["id"], 0) + 1
    print("id | text | desc | class | clickable | bounds | selector")
    seen = set()
    for e in nodes:
        labelled = e["text"] or e["desc"] or e["hint"]
        # an id alone is only worth showing on something the user can act on
        actionable_id = e["id"] and (e["clickable"] or e["cls"] in INPUTS)
        if not show_all and not (labelled or actionable_id):
            continue
        if show_all and not (labelled or e["id"] or e["clickable"]):
            continue
        id_short = e["id"].split(":id/", 1)[-1] if ":id/" in e["id"] else e["id"]
        flags = "yes" if e["clickable"] else "no"
        if not e["enabled"]:
            flags += ",disabled"
        if e["checked"]:
            flags += ",checked"
        text = e["text"] or (("hint=" + e["hint"]) if e["hint"] else "")
        line = " | ".join(clean(x) for x in (id_short, text, e["desc"], e["cls"], flags, e["bounds"], selector(e, id_counts)))
        if line in seen:
            continue
        seen.add(line)
        print(line)
    print("-- %d elements" % len(seen))


if __name__ == "__main__":
    main()
