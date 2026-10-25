#!/usr/bin/env python3
"""Audit: every localized key used by the sources must exist in the string
catalog and be translated for all 11 supported languages.

Two lookup mechanisms are covered:

* explicit `L("key")` calls,
* SwiftUI `LocalizedStringKey` literals (`Text("...")` and friends), which are
  resolved through the catalog automatically.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "Resilix" / "Resources" / "Localizable.xcstrings"
LANGS = ["en", "hi", "te", "ta", "kn", "ml", "mr", "bn", "gu", "pa", "ur"]

L_CALL = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"\s*\)')
VIEWS = [
    "Text", "Label", "Button", "navigationTitle", "Section", "Picker", "TextField",
    "SecureField", "Toggle", "Menu", "ContentUnavailableView", "confirmationDialog",
    "alert", "DisclosureGroup", "Link", "GroupBox", "Tab", "toolbarTitle",
    "NavigationLink", "LabeledContent", "ToolbarItem", "ShareLink", "EditButton",
]
PLAIN = re.compile(r"\b(" + "|".join(VIEWS) + r")\s*\(\s*\"((?:[^\"\\]|\\.)*)\"\s*[,)]")
INTERP = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")


def unescape(literal: str) -> str:
    return literal.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t")


def to_key(literal: str) -> str:
    return unescape(INTERP.sub("%@", literal))


referenced = {}
for path in sorted(ROOT.rglob("*.swift")):
    text = path.read_text()
    rel = str(path.relative_to(ROOT))
    for match in L_CALL.finditer(text):
        key = unescape(match.group(1))
        if key.strip():
            referenced.setdefault(key, set()).add(rel)
    for match in PLAIN.finditer(text):
        key = to_key(match.group(2))
        if key.strip():
            referenced.setdefault(key, set()).add(rel)

catalog = json.loads(CATALOG.read_text())["strings"]

missing = sorted(k for k in referenced if k not in catalog and k.strip())
untranslated = []
placeholder_issues = []
for key in sorted(referenced):
    entry = catalog.get(key)
    if not entry:
        continue
    locs = entry.get("localizations", {})
    for lang in LANGS:
        value = locs.get(lang, {}).get("stringUnit", {}).get("value")
        if not value:
            untranslated.append(f"{key} [{lang}]")
            continue
        if key.count("%@") != value.count("%@"):
            placeholder_issues.append(f"{key} [{lang}] key={key.count('%@')} value={value.count('%@')}")

orphans = sorted(k for k in catalog if k not in referenced)

print(f"referenced keys: {len(referenced)}")
print(f"catalog keys:    {len(catalog)}")
print(f"missing from catalog: {len(missing)}")
for k in missing:
    print("  MISSING:", k)
print(f"missing translations: {len(untranslated)}")
for k in untranslated[:40]:
    print("  UNTRANSLATED:", k)
print(f"placeholder count mismatches: {len(placeholder_issues)}")
for k in placeholder_issues[:40]:
    print("  PLACEHOLDER:", k)
print(f"orphan catalog keys (never used): {len(orphans)}")
for k in orphans[:40]:
    print("  ORPHAN:", k)

sys.exit(1 if (missing or untranslated or placeholder_issues) else 0)
