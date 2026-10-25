#!/usr/bin/env python3
"""Finds local `var`s that are mutated inside an escaping closure.

Xcode reports this as: "Reference to captured var 'x' in concurrently-executing
code; this is an error in the Swift 6 language mode". It shipped twice —
`didComplete` in PermissionService and `resumed` in PeerToPeerWiFiTransport —
both used as "only resume the continuation once" flags inside
`stateUpdateHandler` closures.

The check is deliberately narrow, because a broad one would drown in noise:

* only `var` declared inside a function body counts;
* it is only reported when the variable is *mutated* (`x =`, `x +=`, `x.y =`)
  inside a closure whose opening brace is classified as a closure
  (`Task { }`, `.something = { }`, `queue.async { }`, `{ ... in }`), not inside
  a control-flow block of the same function;
* reading the variable inside a closure is not reported.

Usage:  python3 Tools/capturecheck.py [--verbose]
Exit code 0 when nothing was found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Resilix"] + ([ROOT / "ResilixTests"] if (ROOT / "ResilixTests").is_dir() else [])

CONTROL_FLOW = (
    "if", "else", "guard", "for", "while", "switch", "do", "defer", "catch",
    "repeat", "case", "default", "func", "init", "var", "let", "get", "set",
)


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


def brace_kinds(source: str) -> dict[int, str]:
    """classify every `{` in the file as 'closure', 'function' or 'block'."""
    kinds: dict[int, str] = {}
    for m in re.finditer(r"\bfunc\s+[A-Za-z_]\w*\s*(?:<[^>]*>)?\s*\(", source):
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
        if brace >= 0:
            kinds[brace] = "function"
    for pos, ch in enumerate(source):
        if ch != "{" or pos in kinds:
            continue
        before = source[max(0, pos - 160) : pos].rstrip()
        # trailing closure or closure assigned to a member / passed as argument
        if re.search(r"(?:=|,|\(|\breturn|\))\s*$", before) and re.search(r"\w", before[-40:] if before else ""):
            kinds[pos] = "closure"
            continue
        word = re.search(r"([A-Za-z_]\w*)\s*$", before)
        if word and word.group(1) not in CONTROL_FLOW:
            kinds[pos] = "closure"
            continue
        kinds[pos] = "block"
    return kinds


def function_ranges(source: str) -> list[tuple[int, int]]:
    """(body start, body end) for every function/method/initialiser."""
    ranges: list[tuple[int, int]] = []
    for m in re.finditer(r"\b(?:func|init)\s+[A-Za-z_]?\w*\s*(?:<[^>]*>)?\s*\(", source):
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
        end = matching(source, brace)
        if end > 0:
            ranges.append((brace, end))
    return ranges


# Text immediately before the closure's `{` (the brace itself is not included).
ASYNC_CLOSURE = re.compile(
    r"(?:=\s*|\bTask\s*(?:\([^)]*\))?\s*|\basync\s*|\bsink\s*|\bin\s*|"
    r"\bwithChecked(?:Throwing)?Continuation\s*|\baddTask\s*(?:\([^)]*\))?\s*)$"
)


def check_file(path: Path, source: str) -> list[str]:
    ranges = function_ranges(source)
    if not ranges:
        return []

    problems: list[str] = []
    seen: set[str] = set()

    for body_start, body_end in ranges:
        body = source[body_start:body_end]
        # locals declared anywhere inside this function
        locals_ = {m.group(1) for m in re.finditer(r"(?<![\w.])var\s+([A-Za-z_]\w*)\s*(?::|=)", body)}
        # skip names that also exist as members (`var x` at member level is not
        # visible here because only the function body is scanned)
        for name in sorted(locals_):
            if name in seen:
                continue
            mutation = re.compile(
                rf"(?<![\w.]){re.escape(name)}\s*(?:\+=|-=|\*=|/=|=(?!=))"
            )
            for m in mutation.finditer(body, 1):
                pos = body_start + m.start()
                # `var resumed = false` is a declaration, not a mutation
                if re.search(r"\bvar\s+$", source[max(0, pos - 40) : pos]):
                    continue
                # brace chain between the function body and the mutation
                stack = [body_start]
                j = body_start + 1
                while j < pos:
                    if source[j] == "{":
                        stack.append(j)
                    elif source[j] == "}":
                        if len(stack) > 1:
                            stack.pop()
                    j += 1
                if stack[-1] == body_start:
                    continue  # mutation is at function level: a plain local var
                # A mutation is unsafe when *any* enclosing brace is a closure
                # body; the innermost one is often just an `if`/`guard` block.
                in_closure = False
                for brace in stack[1:]:
                    opener_context = source[max(0, brace - 60) : brace].rstrip()
                    if ASYNC_CLOSURE.search(opener_context):
                        in_closure = True
                        break
                if not in_closure:
                    continue
                line = source[:pos].count("\n") + 1
                problems.append(
                    f"{path.relative_to(ROOT)}:{line}  local `var {name}` is mutated inside a "
                    f"closure — a captured mutable var is an error under Swift 6"
                )
                seen.add(name)
                break
    return problems


def main() -> int:
    verbose = "--verbose" in sys.argv
    problems: list[str] = []
    total = 0
    for path in sorted(p for root in SOURCES for p in root.rglob("*.swift")):
        total += 1
        problems.extend(check_file(path, strip_comments_and_strings(path.read_text())))

    print(f"files scanned: {total}")
    print(f"captured vars mutated in closures: {len(problems)}")
    for entry in problems:
        print("  " + entry)
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
