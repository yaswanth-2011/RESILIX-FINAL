#!/usr/bin/env python3
"""Finds calls to methods that do not exist on the receiver's declared type.

Shipped bugs this covers: `meshController?.processQueuedPackets()` where
`MeshController` only declares `processQueue()`.  Xcode reports it as
"value of type 'MeshController' has no member 'processQueuedPackets'"; the
syntax parser cannot.

How it works
------------
1. Index every project type (class/struct/enum/actor/protocol) together with
   all of its declared members, including members added in extensions.
2. Index properties that carry an explicit project type
   (`private var meshController: MeshController?`).
3. For every `property.method(` (and `property?.method(`) call, check the
   member exists on that type.

Two confidence levels are reported:

* **unknown symbol** — the method name exists on no project type at all. This
  is reported as a failure.
* **not on this type** — the name exists elsewhere in the project but not on
  the receiver's type. Printed for review, because protocols and superclasses
  can legitimately contribute members that this tool cannot see.

System members inherited from Swift/Foundation/Combine (`objectWillChange`,
`description`, ...) are allow-listed.

Usage:  python3 Tools/memberresolve.py [--quiet]
Exit code 0 when no unknown symbols were found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Resilix"

TYPE_KEYWORDS = ("class", "struct", "enum", "actor", "protocol")

# Members provided by protocols/superclasses the tool cannot follow.
ALLOWED = {
    "objectWillChange", "description", "debugDescription", "hashValue", "hash",
    "init", "self", "encode", "decode", "isEqual", "copy", "mutableCopy",
    "responds", "perform", "valueForKey", "setValue", "description",
    "withLock", "lock", "unlock", "tryLock", "signal", "wait", "broadcast",
    "send", "receive", "cancel", "resume", "suspend", "finish", "yield",
    "append", "removeAll", "map", "compactMap", "flatMap", "filter",
    "forEach", "contains", "first", "last", "sorted", "reduce", "joined",
}


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


def depth_table(text: str) -> list[int]:
    """Brace depth before each character (0 == top level)."""
    depths = [0] * (len(text) + 1)
    depth = 0
    for i, ch in enumerate(text):
        depths[i] = depth
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
    depths[len(text)] = depth
    return depths


def collect_members(body: str) -> set[str]:
    members: set[str] = set()
    for m in re.finditer(r"\bfunc\s+([A-Za-z_]\w*)", body):
        members.add(m.group(1))
    for m in re.finditer(r"\b(?:var|let)\s+([A-Za-z_]\w*)", body):
        members.add(m.group(1))
    for m in re.finditer(r"\bcase\s+([\w\s,]+)", body):
        for token in m.group(1).split(","):
            name = token.strip().split("(")[0].strip()
            if re.fullmatch(r"[A-Za-z_]\w*", name):
                members.add(name)
    for m in re.finditer(r"\btypealias\s+([A-Za-z_]\w*)", body):
        members.add(m.group(1))
    for m in re.finditer(rf"\b(?:{'|'.join(TYPE_KEYWORDS)})\s+([A-Za-z_]\w*)", body):
        members.add(m.group(1))
    return members


def index_types(files: dict[Path, str]) -> dict[str, set[str]]:
    """Members of every type the project *declares*.

    Types the project only extends (`extension String`, `extension Color`) are
    ignored: they are system types, and treating them as project types turns
    every stdlib call into a false positive.
    """
    declared: set[str] = set()
    bodies: list[tuple[str, str]] = []
    for source in files.values():
        for m in re.finditer(rf"\b(?:{'|'.join(TYPE_KEYWORDS)})\s+([A-Za-z_]\w*)\b[^{{]*\{{", source):
            end = matching(source, m.end() - 1)
            if end < 0:
                continue
            declared.add(m.group(1))
            bodies.append((m.group(1), source[m.end() : end]))
        for m in re.finditer(r"\bextension\s+([A-Za-z_]\w*)\b[^{]*\{", source):
            end = matching(source, m.end() - 1)
            if end < 0:
                continue
            bodies.append((m.group(1), source[m.end() : end]))

    types: dict[str, set[str]] = {name: set() for name in declared}
    for name, body in bodies:
        if name in declared:
            types[name].update(collect_members(body))
    return types


def index_typed_properties(files: dict[Path, str],
                           types: dict[str, set[str]],
                           depths: dict[Path, list[int]],
                           locals_by_file: dict[Path, set[str]]) -> dict[str, str]:
    """property name -> project type name (only unambiguous member-level ones).

    Local variables that happen to share a property's name are the main source
    of false positives (`let engine = Engine(...)` next to a view's
    `private let engine: ResilixLocalAI`), so a declaration only counts when it
    sits at member level (depth 0 or 1).
    """
    candidates: dict[str, set[str]] = {}
    for path, source in files.items():
        table = depths[path]
        for m in re.finditer(r"\b(?:let|var)\s+([A-Za-z_]\w*)\s*:\s*([A-Z][A-Za-z_\[\]<> ]*?)\s*[?!]?\s*(?:=|$|\n|\{)", source):
            prop, type_name = m.group(1), m.group(2).strip()
            if table[m.start()] >= 2:
                locals_by_file.setdefault(path, set()).add(prop)
                continue
            candidates.setdefault(prop, set()).add(type_name)
        # Locals written without a type annotation (`let engine = Engine(...)`)
        # still shadow a same-named property.
        for m in re.finditer(r"\b(?:let|var)\s+([A-Za-z_]\w*)\s*=(?!=)", source):
            if table[m.start()] >= 2:
                locals_by_file.setdefault(path, set()).add(m.group(1))
        # `for transport in ...` binds a local with the same name.
        for m in re.finditer(r"\bfor\s+([A-Za-z_]\w*)\s+in\b", source):
            locals_by_file.setdefault(path, set()).add(m.group(1))
        # Member-level properties initialised from a project type
        # (`private static let state = LanguageState()`) make the name
        # ambiguous when another member of the same name exists.
        for m in re.finditer(r"\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*([A-Z][A-Za-z_]\w*)\s*\(", source):
            if table[m.start()] <= 1 and m.group(2) in types:
                candidates.setdefault(m.group(1), set()).add(m.group(2))
    return {prop: next(iter(names))
            for prop, names in candidates.items()
            if len(names) == 1 and next(iter(names)) in types}


def main() -> int:
    quiet = "--quiet" in sys.argv
    files: dict[Path, str] = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        files[path] = strip_comments_and_strings(path.read_text())

    types = index_types(files)
    depths = {path: depth_table(source) for path, source in files.items()}
    locals_by_file: dict[Path, set[str]] = {}
    properties = index_typed_properties(files, types, depths, locals_by_file)
    all_members: set[str] = set()
    for members in types.values():
        all_members |= members

    unknown: list[str] = []
    suspicious: list[str] = []
    checked = 0
    for path, source in files.items():
        for m in re.finditer(r"\b([a-z_]\w*)\s*\??\.\s*([A-Za-z_]\w*)\s*\(", source):
            receiver, method = m.group(1), m.group(2)
            type_name = properties.get(receiver)
            if type_name is None:
                continue
            if receiver in locals_by_file.get(path, set()):
                continue  # a local variable shadows the property
            checked += 1
            if method in types[type_name] or method in ALLOWED:
                continue
            line = source[: m.start()].count("\n") + 1
            location = f"{path.relative_to(ROOT)}:{line}  {receiver}.{method}(...) — {type_name}"
            if method not in all_members:
                unknown.append(location)
            else:
                owners = sorted(t for t, members in types.items() if method in members)[:4]
                suspicious.append(f"{location} (declared on {', '.join(owners)})")

    print(f"project types: {len(types)}")
    print(f"typed properties: {len(properties)}")
    print(f"receiver calls checked: {checked}")
    print(f"unknown symbols: {len(unknown)}")
    for entry in unknown:
        print("  " + entry)
    if suspicious and not quiet:
        print(f"not on the receiver's type (needs review): {len(suspicious)}")
        for entry in suspicious:
            print("  " + entry)
    return 0 if not unknown else 1


if __name__ == "__main__":
    sys.exit(main())
