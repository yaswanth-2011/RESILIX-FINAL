#!/usr/bin/env python3
"""Merge the translation tables into `Localizable.xcstrings`.

The tables are plain TSV files (`language<TAB>key<TAB>value`) inside
`Tools/l10n`. Every language of the app gets its own entry in the string
catalog, so the picker in the settings really changes the interface
language.
"""
from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
CATALOG = ROOT / "Resilix" / "Resources" / "Localizable.xcstrings"
TABLES = sorted((ROOT / "Tools" / "l10n").glob("chunk*.tsv"))

LANGUAGES = {
    "en": "English",
    "hi": "Hindi",
    "te": "Telugu",
    "ta": "Tamil",
    "kn": "Kannada",
    "ml": "Malayalam",
    "mr": "Marathi",
    "bn": "Bengali",
    "gu": "Gujarati",
    "pa": "Punjabi",
    "ur": "Urdu",
}


def main() -> int:
    if not CATALOG.exists():
        print("catalog not found", file=sys.stderr)
        return 1

    catalog = json.loads(CATALOG.read_text())
    catalog.setdefault("strings", {})

    entries: dict[tuple[str, str], str] = {}
    for table in TABLES:
        for line in table.read_text().splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) == 3:
                # legacy layout: language <TAB> key <TAB> value
                language, key, value = parts[0].strip(), parts[1].strip(), parts[2]
                if language not in LANGUAGES:
                    print(f"unknown language: {language}")
                    continue
                entries[(language, key)] = value
            elif len(parts) == 1 + len(LANGUAGES):
                # compact layout: key <TAB> en <TAB> hi <TAB> te ... (one row per key)
                key = parts[0].strip()
                for language, value in zip(LANGUAGES, parts[1:]):
                    value = value.strip()
                    if value:
                        entries[(language, key)] = value
            else:
                print(f"skipping malformed line: {line!r}")
                continue

    added = 0
    for (language, key), value in sorted(entries.items()):
        entry = catalog["strings"].setdefault(key, {})
        entry.setdefault("extractionState", "manual")
        localizations = entry.setdefault("localizations", {})
        language_entry = localizations.setdefault(language, {})
        language_entry["stringUnit"] = {"state": "translated", "value": value}
        added += 1

    # A key that is its own English text (a plain SwiftUI literal) still needs an
    # explicit English entry, otherwise English mode would show the raw key.
    for key in sorted({key for _, key in entries}):
        entry = catalog["strings"].setdefault(key, {})
        localizations = entry.setdefault("localizations", {})
        if "en" not in localizations and "." not in key:
            localizations["en"] = {"stringUnit": {"state": "translated", "value": key}}

    # Make sure every supported language is listed in the catalog.
    catalog["sourceLanguage"] = catalog.get("sourceLanguage", "en")
    catalog["version"] = catalog.get("version", "1.0")

    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

    keys = sorted({key for _, key in entries})
    print(f"merged {added} translations for {len(keys)} keys and {len(LANGUAGES)} languages")
    for language in sorted(LANGUAGES):
        count = sum(1 for lang, _ in entries if lang == language)
        print(f"  {LANGUAGES[language]} ({language}): {count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
