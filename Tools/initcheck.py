#!/usr/bin/env python3
"""Static initialiser checker for Resilix.

Why this exists
---------------
`xcodebuild` is not available in the authoring environment, so a wrong
argument label in a struct call site (for example `NearbyDevice(name: ...)`
when the type only declares `init(node: ...)`) cannot be caught by compiling.
The Swift parser used by `swiftcheck.py` only proves the syntax is valid.

When a struct declares at least one initialiser in its own body, Swift stops
synthesising the memberwise initialiser.  That makes the rule for these types
exact and noise-free:

    every call site must match one of the declared initialisers

Structs *without* an explicit initialiser keep their memberwise initialiser,
which is far harder to reconstruct statically (property wrappers, defaults,
computed properties), so they are reported as "skipped" rather than guessed.

The checker is deliberately conservative: anything it cannot parse with
confidence is skipped instead of reported, because a false failure here is
worse than a missed one -- `swiftcheck.py` remains the gate for syntax.

Usage:  python3 Tools/initcheck.py [--verbose]
Exit code 0 when no mismatches were found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Resilix"

DECL_MODIFIERS = r"(?:(?:public|internal|private|fileprivate|open|final)\s+)*"


def strip_comments_and_strings(text: str) -> str:
    """Blanks out comments and string literals, preserving line structure."""
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
            # multi-line string: blank it entirely, keeping newlines so that
            # line numbers stay correct.  Braces inside it must not be counted.
            out.append("   ")
            i += 3
            end = text.find('"""', i)
            if end < 0:
                end = n
            block = text[i:end]
            out.append("".join("\n" if ch == "\n" else " " for ch in block))
            i = end + 3
            out.append("   ")
        elif c == '"':
            # single-line string; escapes are handled below
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
    """Index of the bracket that closes the one at `start`, or -1."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    opener = text[start]
    closer = pairs[opener]
    depth = 0
    for i in range(start, len(text)):
        if text[i] == opener:
            depth += 1
        elif text[i] == closer:
            depth -= 1
            if depth == 0:
                return i
    return -1


def split_top_level(args: str) -> list[str]:
    """Splits an argument list on commas that are not nested."""
    parts, depth, current = [], 0, []
    for ch in args:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    tail = "".join(current)
    if tail.strip():
        parts.append(tail)
    return parts


def parse_params(params: str) -> list[tuple[str, bool]] | None:
    """Returns [(label, has_default)] for a Swift parameter list."""
    result: list[tuple[str, bool]] = []
    for raw in split_top_level(params):
        part = raw.strip()
        if not part:
            continue
        # drop generic where-clauses / attributes
        if part.startswith("@"):
            part = part.split(" ", 1)[1] if " " in part else part
        head = part.split(":", 1)[0].strip()
        if not head:
            return None
        words = head.split()
        if len(words) == 1:
            label = words[0]
            if label == "_":
                result.append(("_", "=" in part))
                continue
            label = words[0]
        elif len(words) == 2:
            label = words[0]  # external name
            if label == "_":
                result.append(("_", "=" in part))
                continue
        else:
            return None
        result.append((label, part.rsplit("=", 1)[0].strip() != part.strip() if "=" in part else False))
    return result


def brace_depth(text: str, index: int) -> int:
    """Brace nesting depth at `index` (0 == member level of the body)."""
    depth = 0
    for i in range(min(index, len(text))):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
    return depth


def collect_declarations(source: str) -> dict[str, list[list[tuple[str, bool]]]]:
    """name -> list of parameter lists for structs declaring an `init`."""
    found: dict[str, list[list[tuple[str, bool]]]] = {}
    for m in re.finditer(rf"\bstruct\s+(\w+)\b[^{{]*\{{", source):
        name = m.group(1)
        body_start = m.end() - 1
        body_end = matching(source, body_start)
        if body_end < 0:
            continue
        body = source[body_start + 1 : body_end]
        inits: list[list[tuple[str, bool]]] = []
        for im in re.finditer(rf"(?<![\w.]){DECL_MODIFIERS}init\??\s*\(", body):
            # `Text(.init(...))` is a call, not a declaration, and initialisers
            # nested in closures are not member-level.
            if body[: im.start()].rstrip().endswith("."):
                continue
            if brace_depth(body, im.start()) != 0:
                continue
            open_paren = im.end() - 1
            close_paren = matching(body, open_paren)
            if close_paren < 0:
                continue
            params = parse_params(body[open_paren + 1 : close_paren])
            if params is not None:
                inits.append(params)
        if inits:
            found[name] = inits
    return found


def check_call_site(labels: list[str], has_trailing_closure: bool, inits) -> bool:
    for params in inits:
        expected = [p[0] for p in params if p[0] != "_"]
        required = [p[0] for p in params if not p[1] and p[0] != "_"]
        given = list(labels)
        if has_trailing_closure:
            # a trailing closure fills the first parameter that takes a closure
            for label in expected:
                if label not in given:
                    given.append(label)
                    break
            else:
                given.append("__closure__")
        if not set(given) <= set(expected):
            continue
        if not set(required) <= set(given):
            continue
        # positional arguments are not modelled, so accept a prefix match
        return True
    return False


def main() -> int:
    verbose = "--verbose" in sys.argv
    declarations: dict[str, list[list[tuple[str, bool]]]] = {}
    files: dict[Path, str] = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        raw = path.read_text()
        clean = strip_comments_and_strings(raw)
        files[path] = clean
        declarations.update(collect_declarations(clean))

    # A duplicate initialiser signature is a hard compile error ("invalid
    # redeclaration").  This check exists because that mistake was actually
    # made once while patching a struct that already declared the initialiser.
    duplicates: list[str] = []
    for name, inits in sorted(declarations.items()):
        seen: set[tuple[tuple[str, bool], ...]] = set()
        for params in inits:
            signature = tuple(params)
            if signature in seen:
                duplicates.append(f"{name}{signature}")
            seen.add(signature)

    mismatches: list[str] = []
    checked = 0
    for path, source in files.items():
        for m in re.finditer(r"\b([A-Z]\w*)\s*\(", source):
            name = m.group(1)
            if name not in declarations:
                continue
            # skip the declaration itself: `struct X` / `init` lines do not match
            prefix = source[max(0, m.start() - 40) : m.start()]
            if re.search(r"\b(?:struct|enum|class|extension|func|init)\s*$", prefix):
                continue
            open_paren = m.end() - 1
            close_paren = matching(source, open_paren)
            if close_paren < 0:
                continue
            given = []
            ok = True
            for part in split_top_level(source[open_paren + 1 : close_paren]):
                if not part.strip():
                    continue
                lm = re.match(r"\s*(\w+)\s*:", part)
                if not lm:
                    ok = False  # unlabelled argument: positional init not modelled
                    break
                given.append(lm.group(1))
            if not ok:
                continue
            after = source[close_paren + 1 : close_paren + 80]
            has_trailing = bool(re.match(r"\s*\{", after))
            checked += 1
            if not check_call_site(given, has_trailing, declarations[name]):
                line = source[: m.start()].count("\n") + 1
                expected = "; ".join(
                    "(" + ", ".join(("!" if not d else "") + l for l, d in params) + ")"
                    for params in declarations[name]
                )
                mismatches.append(
                    f"{path.relative_to(ROOT)}:{line}  {name}({', '.join(given)})\n"
                    f"    declared: {expected}"
                )

    if duplicates:
        print(f"duplicate initialiser signatures: {len(duplicates)}")
        for entry in duplicates:
            print(f"  {entry}")

    print(f"types with explicit initialisers: {len(declarations)}")
    print(f"call sites checked: {checked}")
    if verbose:
        for name, inits in sorted(declarations.items()):
            print(f"  {name}: {len(inits)} init(s)")
    if mismatches or duplicates:
        print(f"\n=== mismatches: {len(mismatches)} ===")
        for entry in mismatches:
            print("  " + entry)
        return 1
    print("mismatches: 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
