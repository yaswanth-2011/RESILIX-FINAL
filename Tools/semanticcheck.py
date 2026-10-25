#!/usr/bin/env python3
"""Two semantic checks that Xcode reports as hard errors but the syntax parser
cannot see.

1. `try` applied to a call that cannot throw
   -------------------------------------------
   `try await decryptPayload(packet)` fails with "No calls to throwing
   functions occur within 'try' expression" when the function is not
   `throws`.  This shipped once.  The checker indexes every function declared
   in the project, then flags `try`/`try await` calls whose target name is
   declared in the project and none of those declarations throws.  Names that
   are ambiguous (some declaring versions throw, some do not) are skipped so
   the check stays free of false positives.

2. `NSLock.lock()` / `unlock()` inside an asynchronous function
   -------------------------------------------------------------
   Those methods are unavailable from async contexts ("use async-safe scoped
   locking instead"); `lock.withLock { }` is the replacement.  This shipped
   once too.

Usage:  python3 Tools/semanticcheck.py [--verbose]
Exit code 0 when nothing was found.
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


def collect_functions(files: dict[Path, str]) -> dict[str, list[bool]]:
    """Name -> list of `throws` flags, one per declaration."""
    index: dict[str, list[bool]] = {}
    for source in files.values():
        for m in re.finditer(r"\bfunc\s+([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\(", source):
            # signature runs to the body brace (or to the end of the line)
            depth, i = 0, m.end() - 1
            n = len(source)
            while i < n:
                if source[i] == "(":
                    depth += 1
                elif source[i] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            signature = source[m.end() : i + 1]
            tail = source[i + 1 : i + 200]
            header = signature + tail.split("{", 1)[0]
            index.setdefault(m.group(1), []).append("throws" in header or "rethrows" in header)
    return index


def check_try_calls(files: dict[Path, str], functions: dict[str, list[bool]]) -> list[str]:
    problems: list[str] = []
    for path, source in files.items():
        for m in re.finditer(r"\btry\b(?!\s*[?!])\s+(?:await\s+)?([A-Za-z_]\w*)\s*\(", source):
            name = m.group(1)
            declarations = functions.get(name)
            if not declarations:
                continue
            if any(declarations):
                continue  # at least one overload can throw: not provable
            line = source[: m.start()].count("\n") + 1
            problems.append(
                f"{path.relative_to(ROOT)}:{line}  `try` on non-throwing {name}(...) "
                f"({len(declarations)} declaration(s), none throws)"
            )
    return problems


def async_function_bodies(source: str):
    """Yields (name, body_start, body_end) for every `async` function."""
    for m in re.finditer(r"\bfunc\s+([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\(", source):
        depth, i, n = 0, m.end() - 1, len(source)
        while i < n:
            if source[i] == "(":
                depth += 1
            elif source[i] == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        header = source[i + 1 : source.find("{", i + 1)] if "{" in source[i + 1 :] else ""
        if not re.search(r"\basync\b", header):
            continue
        brace = source.find("{", i + 1)
        if brace < 0:
            continue
        end = matching(source, brace)
        if end < 0:
            continue
        yield m.group(1), brace, end


def check_lock_in_async(files: dict[Path, str]) -> list[str]:
    problems: list[str] = []
    for path, source in files.items():
        for name, start, end in async_function_bodies(source):
            body = source[start:end]
            for lm in re.finditer(r"\.\s*(?:lock|unlock)\s*\(\s*\)", body):
                line = source[: start + lm.start()].count("\n") + 1
                problems.append(
                    f"{path.relative_to(ROOT)}:{line}  `{lm.group(0).strip()}` inside async "
                    f"func {name}(...) — use lock.withLock"
                )
    return problems


def main() -> int:
    verbose = "--verbose" in sys.argv
    files: dict[Path, str] = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        files[path] = strip_comments_and_strings(path.read_text())

    functions = collect_functions(files)
    try_problems = check_try_calls(files, functions)
    lock_problems = check_lock_in_async(files)

    print(f"functions indexed: {len(functions)}")
    if verbose:
        throwing = sum(1 for flags in functions.values() if any(flags))
        print(f"  names with at least one throwing declaration: {throwing}")

    total = 0
    for title, problems in (("try on non-throwing call", try_problems),
                            ("lock/unlock inside async", lock_problems)):
        print(f"{title}: {len(problems)}")
        for p in problems:
            print("  " + p)
        total += len(problems)

    return 0 if total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
