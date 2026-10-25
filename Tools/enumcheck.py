#!/usr/bin/env python3
"""Checks explicitly-qualified enum member references.

`xcodebuild` is unavailable in the authoring environment, so referencing an
enum case that does not exist (`DeliveryState.sending`, say) would otherwise
only surface when the project is opened in Xcode.  That class of mistake was
made for real in this project, so it is worth a dedicated check.

Only *explicitly qualified* references (`EnumName.caseName`) are examined.
Those are unambiguous: the token before the dot names a locally declared enum,
so the token after the dot must be one of its cases or one of its other
declared members (computed property, static function, typealias, nested type).

Implicit `.caseName` references are deliberately not checked: their type comes
from inference and guessing it statically produces false positives.

Usage:  python3 Tools/enumcheck.py [--verbose]
Exit code 0 when no missing cases were found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Resilix"


def strip_comments_and_strings(text: str) -> str:
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            depth = 1
            out.append("  ")
            i += 2
            while i < n and depth:
                if text.startswith("/*", i):
                    depth += 1
                    out.append("  ")
                    i += 2
                elif text.startswith("*/", i):
                    depth -= 1
                    out.append("  ")
                    i += 2
                else:
                    out.append("\n" if text[i] == "\n" else " ")
                    i += 1
        elif text.startswith('"""', i):
            out.append("   ")
            i += 3
            end = text.find('"""', i)
            if end < 0:
                end = n
            out.append("".join("\n" if ch == "\n" else " " for ch in text[i:end]))
            i = end + 3
            out.append("   ")
        elif c == '"':
            out.append(" ")
            i += 1
            while i < n:
                if text[i] == "\\":
                    out.append("  ")
                    i += 2
                    continue
                if text[i] == '"':
                    out.append(" ")
                    i += 1
                    break
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def matching(text: str, start: int) -> int:
    pairs = {"(": ")", "[": "]", "{": "}"}
    opener, closer = text[start], pairs[text[start]]
    depth = 0
    for i in range(start, len(text)):
        if text[i] == opener:
            depth += 1
        elif text[i] == closer:
            depth -= 1
            if depth == 0:
                return i
    return -1


def collect_enums(source: str) -> dict[str, tuple[set[str], set[str]]]:
    """name -> (case names, other member names)."""
    enums: dict[str, tuple[set[str], set[str]]] = {}
    for m in re.finditer(r"\benum\s+(\w+)\b[^{]*\{", source):
        name = m.group(1)
        end = matching(source, m.end() - 1)
        if end < 0:
            continue
        body = source[m.end() : end]
        cases: set[str] = set()
        # Case clauses are matched per line: a greedy match would swallow
        # several `case` lines and then only keep the first one.
        for line in body.split("\n"):
            cm = re.match(r"\s*(?:indirect\s+)?case\s+(.+?)\s*(?://.*)?$", line)
            if not cm:
                continue
            for piece in cm.group(1).split(","):
                token = piece.strip().split("(")[0].split("=")[0].strip()
                token = re.sub(r"^(?:let|var)\s+", "", token)
                if re.fullmatch(r"[A-Za-z_]\w*", token):
                    cases.add(token)
        others: set[str] = set()
        for om in re.finditer(
            r"\b(?:var|let|func|static|typealias|struct|enum|class|init)\s+(?:\w+\s+)?(\w+)",
            body,
        ):
            others.add(om.group(1))
        enums[name] = (cases, others)
    return enums


def main() -> int:
    verbose = "--verbose" in sys.argv
    enums: dict[str, tuple[set[str], set[str]]] = {}
    files: dict[Path, str] = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        clean = strip_comments_and_strings(path.read_text())
        files[path] = clean
        enums.update(collect_enums(clean))

    # names that are also declared as structs/classes/typealiases are ambiguous
    other_types = set()
    for source in files.values():
        other_types.update(m.group(1) for m in re.finditer(r"\b(?:struct|class|typealias)\s+(\w+)", source))

    missing: list[str] = []
    checked = 0
    for path, source in files.items():
        for m in re.finditer(r"\b([A-Z]\w*)\.(\w+)", source):
            enum_name, member = m.group(1), m.group(2)
            if enum_name not in enums or enum_name in other_types:
                continue
            checked += 1
            cases, others = enums[enum_name]
            if member in cases or member in others:
                continue
            if member in {"allCases", "rawValue", "init", "self", "Type", "none"}:
                continue
            line = source[: m.start()].count("\n") + 1
            missing.append(f"{path.relative_to(ROOT)}:{line}  {enum_name}.{member} (known: {', '.join(sorted(cases))[:90]})")

    print(f"enums: {len(enums)}")
    print(f"qualified references checked: {checked}")
    if verbose:
        for name, (cases, others) in sorted(enums.items()):
            print(f"  {name}: {len(cases)} case(s)")
    if missing:
        print(f"\n=== unknown enum members: {len(missing)} ===")
        for entry in missing:
            print("  " + entry)
        return 1
    print("unknown enum members: 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
