#!/usr/bin/env python3
"""Find user-visible UI literals that are still hard-coded English.

The audit looks at the argument positions of the SwiftUI APIs that render
text and at the model properties that feed those APIs (`title`, `label`,
`subtitle`, `message`, `placeholder`, `displayName`, …).

Literals that already use `L("…")` or that already exist in the string
catalog are skipped.

Usage:  python3 Tools/l10n/find_ui_literals.py [root]
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "Resilix").resolve()
CATALOG = ROOT.parent / "Resources" / "Localizable.xcstrings"

# SwiftUI call sites whose first argument is rendered to the user.
TEXT_CALLS = (
    "Text", "Button", "Label", "Toggle", "Picker", "Section", "Group",
    "Link", "Menu", "TextField", "SecureField", "TextEditor",
)
# Named arguments that carry user-visible text.
TEXT_PARAMS = (
    "title", "label", "subtitle", "message", "placeholder", "displayName",
    "header", "footer", "prompt", "accessibilityLabel", "accessibilityHint",
    "accessibilityValue", "help", "text", "detail", "caption", "actionTitle",
)
# Model properties whose value is shown to the user.
MODEL_PROPS = ("title", "subtitle", "label", "displayName", "message", "placeholder")

catalog_keys = set()
if CATALOG.exists():
    catalog_keys = set(json.loads(CATALOG.read_text()).get("strings", {}))

lit = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
call_re = re.compile(r"\b(" + "|".join(TEXT_CALLS) + r")\s*\(\s*")
param_re = re.compile(r"[,(\s]\b(" + "|".join(TEXT_PARAMS) + r")\s*:\s*")
prop_re = re.compile(r"\b(" + "|".join(MODEL_PROPS) + r")\s*:\s*")

TECH = re.compile(r"^[A-Za-z0-9_.:/\-]+$")           # identifiers, colours, MIME types
results: list[tuple[str, int, str]] = []
for path in sorted(ROOT.rglob("*.swift")):
    src = path.read_text()
    for m in lit.finditer(src):
        text = m.group(1)
        if not text.strip():
            continue
        if text in catalog_keys:
            continue
        if TECH.match(text) and " " not in text:
            continue
        start = m.start()
        # skip literals that belong to an `L(` call
        prefix = src[max(0, start - 4):start]
        if prefix.rstrip().endswith("L("):
            continue
        window = src[max(0, start - 400):start]
        # find the innermost opening bracket of the call/parameter
        if not (call_re.search(window) or param_re.search(window) or prop_re.search(window)):
            continue
        line = src[:start].count("\n") + 1
        results.append((str(path.relative_to(ROOT)), line, text))

uniq: dict[str, list[str]] = {}
for rel, line, text in results:
    uniq.setdefault(text, []).append(f"{rel}:{line}")

print(f"=== {len(results)} occurrences / {len(uniq)} distinct UI literals ===")
for text in sorted(uniq):
    print(f"{text!r}\t{', '.join(uniq[text][:4])}")
