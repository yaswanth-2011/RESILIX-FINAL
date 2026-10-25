#!/usr/bin/env python3
"""Finds `await` used outside an asynchronous context.

The error Xcode reports is "'async' call in a function that does not support
concurrency". It shipped four times in `RelayQueue`: four members called
`await persist()` while not being `async` themselves. Because `RelayQueue` is
an actor, every member is *called* with `await` from outside, which hides the
fact that a synchronous member cannot suspend internally.

The check walks each file with a context stack:

* a function body inherits `async` from the function's signature;
* `Task { }` / `Task.detached { }` open an asynchronous closure;
* a closure whose header contains `in` and `async` is asynchronous;
* every other brace (`if`, `for`, `do`, `switch`, defer, plain closures)
  inherits the enclosing context.

An `await` (or `for await`) inside a context that is not asynchronous is
reported.

Usage:  python3 Tools/awaitcheck.py [--verbose]
Exit code 0 when nothing was found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Resilix"] + ([ROOT / "ResilixTests"] if (ROOT / "ResilixTests").is_dir() else [])


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


def function_bodies(source: str) -> dict[int, tuple[str, bool]]:
    """Opening-brace position -> (function name, isAsync)."""
    bodies: dict[int, tuple[str, bool]] = {}
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
        brace = source.find("{", i + 1)
        if brace < 0:
            continue
        header = source[i + 1 : brace]
        # a computed property (`var x: Int { ... }`) is not reached here
        bodies[brace] = (m.group(1), bool(re.search(r"\basync\b", header)))
    return bodies


def classify_brace(source: str, pos: int, funcs: dict[int, tuple[str, bool]], parent: bool) -> tuple[bool, str]:
    if pos in funcs:
        name, is_async = funcs[pos]
        return is_async, f"func {name}"
    before = source[max(0, pos - 120) : pos]
    if re.search(r"\bTask(?:\.detached)?\s*(?:<[^>]*>)?\s*(?:\([^)]*\))?\s*$", before) or \
       re.search(r"\baddTask\s*(?:\([^)]*\))?\s*$", before):
        return True, "Task closure"
    # SwiftUI/Foundation closures that are async without saying so.
    if re.search(r"\.(?:task|refreshable)\s*(?:\([^()]*\))?\s*$", before):
        return True, "async SwiftUI closure"
    # closure header: text up to the first `in` inside the block
    close = matching(source, pos)
    header = source[pos + 1 : min(close if close > 0 else pos + 200, pos + 200)]
    header = header.split(" in ", 1)[0] if " in " in header else ""
    if header and re.search(r"\basync\b", header):
        return True, "async closure"
    return parent, "inherited"


def check_file(path: Path, source: str) -> list[str]:
    funcs = function_bodies(source)
    stack: list[tuple[bool, str]] = [(False, "top level")]
    problems: list[str] = []
    i, n = 0, len(source)
    while i < n:
        ch = source[i]
        if ch == "{":
            ctx, kind = classify_brace(source, i, funcs, stack[-1][0])
            stack.append((ctx, kind))
        elif ch == "}":
            if len(stack) > 1:
                stack.pop()
        elif ch in "af":
            m = re.match(r"(?:for\s+)?await\b", source[i:])
            if m and (i == 0 or not (source[i - 1].isalnum() or source[i - 1] == "_")):
                if not stack[-1][0]:
                    line = source[:i].count("\n") + 1
                    problems.append(
                        f"{path.relative_to(ROOT)}:{line}  `await` in {stack[-1][1]} "
                        f"which is not asynchronous"
                    )
                i += m.end()
                continue
        i += 1
    return problems


def main() -> int:
    verbose = "--verbose" in sys.argv
    problems: list[str] = []
    total = 0
    for path in sorted(p for root in SOURCES for p in root.rglob("*.swift")):
        total += 1
        problems.extend(check_file(path, strip_comments_and_strings(path.read_text())))

    print(f"files scanned: {total}")
    print(f"await outside async context: {len(problems)}")
    for entry in problems:
        print("  " + entry)
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
