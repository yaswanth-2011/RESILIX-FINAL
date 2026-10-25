#!/usr/bin/env python3
"""Two view-layer mistakes that the syntax parser cannot see.

1. A SwiftUI modifier without its leading dot
   -------------------------------------------
   ```swift
   Menu { ... } label: { ... }
   accessibilityLabel(Text("x"))     // parsed as a statement, not a modifier
   ```
   Swift then reports the useless chain downstream ("function declares an
   opaque return type, but has no return statements", "result of ... is
   unused"). Two of these shipped.

2. `[weak self]` inside a struct or enum
   -------------------------------------
   `weak` only applies to class-bound types. SwiftUI views are structs, and
   `@State`'s setter is nonmutating, so the closure can update the value
   directly once the capture list is removed.

Usage:  python3 Tools/viewcheck.py [--verbose]
Exit code 0 when nothing was found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Resilix"] + ([ROOT / "ResilixTests"] if (ROOT / "ResilixTests").is_dir() else [])

MODIFIERS = {
    "accessibilityLabel", "accessibilityHidden", "accessibilityHint",
    "accessibilityValue", "accessibilityAddTraits", "accessibilityIdentifier",
    "padding", "frame", "foregroundStyle", "foregroundColor", "background",
    "overlay", "cornerRadius", "clipShape", "font", "opacity", "onTapGesture",
    "onAppear", "onDisappear", "onChange", "onReceive", "onSubmit", "task",
    "sheet", "alert", "confirmationDialog", "toolbar", "navigationTitle",
    "navigationBarTitleDisplayMode", "navigationBarHidden", "symbolEffect",
    "rotationEffect", "scaleEffect", "offset", "tint", "tag", "shadow",
    "contentShape", "lineLimit", "multilineTextAlignment", "textSelection",
    "textCase", "help", "disabled", "buttonStyle", "listRowSeparator",
    "listRowBackground", "scrollContentBackground", "presentationDetents",
    "presentationDragIndicator", "presentationBackground", "refreshable",
    "contextMenu", "swipeActions", "environmentObject", "accentColor",
    "blur", "mask", "layoutPriority", "fixedSize", "aspectRatio",
    "minimumScaleFactor", "truncationMode", "keyboardType", "textContentType",
    "autocorrectionDisabled", "textInputAutocapitalization", "submitLabel",
    "focused", "scrollPosition", "border", "hidden", "zIndex", "coordinateSpace",
    "gesture", "simultaneousGesture", "highPriorityGesture", "hitTesting",
    "allowsHitTesting", "animation", "transition", "id",
}

TYPES = ("class", "struct", "enum", "actor")
REFERENCE_TYPES = {"class", "actor"}


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
    if start >= len(text) or text[start] not in pairs:
        return -1
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


def type_ranges(source: str) -> list[tuple[str, int, int]]:
    found: list[tuple[str, int, int]] = []
    for m in re.finditer(rf"\b({'|'.join(TYPES)})\s+([A-Za-z_]\w*)\b[^{{]*\{{", source):
        end = matching(source, m.end() - 1)
        if end > 0:
            found.append((m.group(1), m.end() - 1, end))
    return found


def check_missing_dot(path: Path, source: str) -> list[str]:
    problems: list[str] = []
    for lineno, line in enumerate(source.split("\n"), start=1):
        m = re.match(r"^(\s+)([a-z][A-Za-z]*)\($|^(\s+)([a-z][A-Za-z]*)\(", line)
        if not m:
            continue
        name = m.group(2) or m.group(4)
        if name not in MODIFIERS:
            continue
        stripped = line.strip()
        if stripped.startswith("."):
            continue
        problems.append(
            f"{path.relative_to(ROOT)}:{lineno}  `{name}(` is missing its leading dot "
            f"(parsed as a separate statement)"
        )
    return problems


def check_weak_self(path: Path, source: str) -> list[str]:
    shapes = type_ranges(source)
    problems: list[str] = []
    for m in re.finditer(r"\[\s*(?:weak|unowned)\s+self\s*\]", source):
        pos = m.start()
        innermost = None
        for kind, start, end in shapes:
            if start < pos < end:
                if innermost is None or start > innermost[1]:
                    innermost = (kind, start, end)
        if innermost is None:
            continue
        if innermost[0] in REFERENCE_TYPES:
            continue
        line = source[:pos].count("\n") + 1
        problems.append(
            f"{path.relative_to(ROOT)}:{line}  `{m.group(0)}` inside a {innermost[0]} "
            f"— weak only applies to classes"
        )
    return problems


def main() -> int:
    verbose = "--verbose" in sys.argv
    dot_problems: list[str] = []
    weak_problems: list[str] = []
    total = 0
    for path in sorted(p for root in SOURCES for p in root.rglob("*.swift")):
        total += 1
        source = strip_comments_and_strings(path.read_text())
        dot_problems.extend(check_missing_dot(path, source))
        weak_problems.extend(check_weak_self(path, source))

    print(f"files scanned: {total}")
    print(f"modifiers missing a dot: {len(dot_problems)}")
    for entry in dot_problems:
        print("  " + entry)
    print(f"weak self in a value type: {len(weak_problems)}")
    for entry in weak_problems:
        print("  " + entry)
    return 0 if not (dot_problems or weak_problems) else 1


if __name__ == "__main__":
    sys.exit(main())
