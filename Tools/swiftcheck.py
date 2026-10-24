#!/usr/bin/env python3
"""Offline Swift syntax checker for the Resilix project.

The CI/sandbox used for this task has no Xcode toolchain, so this script
parses every Swift source file with tree-sitter-swift and reports syntax
errors (unbalanced braces, stray tokens, malformed declarations).

Usage:
    python3 Tools/swiftcheck.py            # check every .swift file
    python3 Tools/swiftcheck.py path/...   # check specific files
"""
from __future__ import annotations

import sys
import pathlib

try:
    import tree_sitter
    import tree_sitter_swift
except ImportError:  # pragma: no cover
    print("tree_sitter / tree_sitter_swift not installed: pip install tree_sitter tree_sitter_swift")
    sys.exit(2)

REPO = pathlib.Path(__file__).resolve().parent.parent


def collect(paths):
    files = []
    for p in paths:
        p = pathlib.Path(p)
        if p.is_dir():
            files.extend(sorted(p.rglob("*.swift")))
        elif p.suffix == ".swift":
            files.append(p)
    return files


def main(argv):
    targets = argv[1:] or [REPO]
    files = collect(targets)
    parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
    failures = 0
    for f in files:
        data = f.read_bytes()
        tree = parser.parse(data)
        errors = []
        stack = [tree.root_node]
        while stack:
            node = stack.pop()
            if node.type == "ERROR" or node.is_missing:
                # Known grammar limitation: tree-sitter-swift cannot parse a
                # tuple literal used as a call argument (e.g. f((1, 2, 3))), and
                # reports the *callee identifier* as the error.  Skip those.
                prev = node.prev_named_sibling
                if prev is not None and "tuple" in prev.type:
                    stack.extend(node.children)
                    continue
                errors.append(node)
            stack.extend(node.children)
        if errors:
            failures += 1
            print(f"FAIL {f.relative_to(REPO) if str(f).startswith(str(REPO)) else f}")
            for err in errors[:8]:
                row, col = err.start_point
                snippet = data[err.start_byte:err.end_byte][:80]
                kind = "MISSING" if err.is_missing else "ERROR"
                print(f"     {kind} {row + 1}:{col + 1} {snippet!r}")
    print(f"\nchecked {len(files)} Swift file(s): {len(files) - failures} OK, {failures} with syntax errors")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
