#!/usr/bin/env python3
"""Wrap already-translated UI literals in `L("…")`.

The string catalog (`Resilix/Resources/Localizable.xcstrings`) already contains
translations for many literals that are still written as raw Swift strings at
their call site. This tool rewrites those call sites to use the `L()` helper so
the screen renders the string in the language the user selected.

Only literals that are *fully* translated (all 11 shipped languages) are wrapped,
and only in positions that are rendered to the user:

* `Text("…")`, `Button("…")`, `Label("…")`, `Toggle(…)`, `Picker(…)`,
  `Section(…)`, `Link(…)`, `Menu(…)`, `TextField(…)`, `SecureField(…)`,
  `TextEditor(…)`, `Group(…)`
* `.alert("…")`, `.confirmationDialog("…")`
* `accessibilityLabel("…")`, `accessibilityHint("…")`, `accessibilityValue("…")`
* named arguments: `title:`, `subtitle:`, `message:`, `placeholder:`,
  `prompt:`, `header:`, `footer:`, `help:`, `label:`, `displayName:`

Literals used as raw values (`case direct = "Direct"`), as identifiers or as
logic comparisons are never touched because they do not match any of the
patterns above.

Usage:  python3 Tools/l10n/wrap_cached.py [--dry]
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / "Resilix"
CATALOG = APP / "Resources" / "Localizable.xcstrings"
DRY = "--dry" in sys.argv

catalog = json.loads(CATALOG.read_text()).get("strings", {})
fully_translated = {
    key for key, value in catalog.items()
    if len(value.get("localizations", {})) >= 11
}

CALL = (r"Text|Button|Label|Toggle|Picker|Section|Link|Menu|TextField|"
        r"SecureField|TextEditor|Group")
PATTERNS = [
    re.compile(r'(\b(?:%s)\(\s*)"((?:[^"\\\n]|\\.)*)"' % CALL),
    re.compile(r'(\.(?:alert|confirmationDialog)\(\s*)"((?:[^"\\\n]|\\.)*)"'),
    re.compile(r'(\b(?:accessibilityLabel|accessibilityHint|accessibilityValue)\(\s*)"((?:[^"\\\n]|\\.)*)"'),
    re.compile(r'(\b(?:title|subtitle|message|placeholder|prompt|header|footer|help|label|displayName)\s*:\s*)"((?:[^"\\\n]|\\.)*)"'),
]


def wrap(text: str) -> tuple[str, int]:
    count = 0
    for pattern in PATTERNS:
        def repl(match: re.Match) -> str:
            nonlocal count
            prefix, literal = match.group(1), match.group(2)
            if literal not in fully_translated:
                return match.group(0)
            if prefix.rstrip().endswith("L("):
                return match.group(0)
            count += 1
            return '%sL("%s")' % (prefix, literal)
        text = pattern.sub(repl, text)
    return text, count


total = 0
for path in sorted(APP.rglob("*.swift")):
    source = path.read_text()
    updated, count = wrap(source)
    if count:
        total += count
        print("%-58s %3d literal(s)" % (path.relative_to(ROOT), count))
        if not DRY:
            path.write_text(updated)
print("total wrapped:", total, "(dry run)" if DRY else "(applied)")
