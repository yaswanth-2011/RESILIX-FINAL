#!/usr/bin/env python3
"""Audit SwiftUI views for plain string literals that bypass the catalog.

SwiftUI initialisers such as `Text("...")` accept a `LocalizedStringKey`, so a
*pure* literal is looked up in `Localizable.xcstrings` automatically and must
therefore exist in the catalog with a translation for all 11 supported
languages. Expressions such as `Text("x" + L("y"))` use the `String` overload
and are handled explicitly by the code, so they are not reported here.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "Resilix" / "Resources" / "Localizable.xcstrings"
LANGS = ["en", "hi", "te", "ta", "kn", "ml", "mr", "bn", "gu", "pa", "ur"]

VIEWS = [
    "Text", "Label", "Button", "navigationTitle", "Section", "Picker", "TextField",
    "SecureField", "Toggle", "Menu", "ContentUnavailableView", "confirmationDialog",
    "alert", "DisclosureGroup", "Link", "GroupBox", "Tab", "toolbarTitle",
    "NavigationLink", "LabeledContent", "ToolbarItem", "ShareLink", "EditButton",
]
PLAIN = re.compile(
    r"\b(" + "|".join(VIEWS) + r")\s*\(\s*\"((?:[^\"\\]|\\.)*)\"\s*[,)]")
INTERP = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")
LETTER = re.compile(r"[A-Za-z]")


def to_key(literal: str) -> str:
    return INTERP.sub("%@", literal).replace('\\"', '"')


catalog = json.loads(CATALOG.read_text())["strings"]
problems = []
symbolic = []

for path in sorted((ROOT / "Resilix").rglob("*.swift")):
    rel = str(path.relative_to(ROOT))
    text = path.read_text()
    for match in PLAIN.finditer(text):
        literal = match.group(2)
        key = to_key(literal)
        line = text[: match.start()].count("\n") + 1
        if not LETTER.search(key):
            # pure punctuation / numbers: identical in every language
            symbolic.append(f"{rel}:{line}: {key!r}")
            continue
        if key not in catalog:
            problems.append(f"{rel}:{line}: MISSING KEY  {key!r}")
            continue
        locs = catalog[key].get("localizations", {})
        empty = [lang for lang in LANGS if not locs.get(lang, {}).get("stringUnit", {}).get("value")]
        if empty:
            problems.append(f"{rel}:{line}: UNTRANSLATED {key!r} -> {empty}")

print(f"symbol-only literals (no translation needed): {len(symbolic)}")
for s in symbolic:
    print("  ", s)
print(f"problems: {len(problems)}")
for p in problems:
    print("  ", p)
sys.exit(1 if problems else 0)
