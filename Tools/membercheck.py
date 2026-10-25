#!/usr/bin/env python3
"""Type-aware member cross-check for the Resilix sources.

The project cannot be compiled in this environment (no Xcode / Swift
toolchain), so this script approximates the compiler's "member does not
exist" diagnostic:

  1. every type declaration (struct / class / enum / actor / extension)
     is indexed together with the members it declares,
  2. every local variable with a known static type is indexed,
  3. every `<receiver>.<member>` access is checked against the index.

It reports *possible* problems only - dynamic members, protocol
requirements and members coming from framework types are not known to the
index and are therefore skipped.

Usage:  python3 Tools/membercheck.py [root]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from tree_sitter import Language, Parser
import tree_sitter_swift

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else "Resilix").resolve()
SEARCH_DIRS = [ROOT, ROOT.parent / "ResilixTests"]

DECL_TYPES = {
    "class_declaration",
    "struct_declaration",
    "enum_declaration",
    "actor_declaration",
    "extension_declaration",
}
TYPE_NAME_NODES = {"type_identifier", "user_type", "identifier", "type_name"}

parser = Parser(Language(tree_sitter_swift.language()))


def parse(path: Path):
    return parser.parse(path.read_bytes())


def type_name_of(node) -> str | None:
    """Name of the declared type of a class/struct/enum/extension node."""
    for child in node.children:
        if child.type in ("type_identifier", "identifier"):
            return child.text.decode()
        if child.type == "user_type":
            for sub in child.children:
                if sub.type in ("type_identifier", "identifier"):
                    return sub.text.decode()
    return None


def collect_members(node) -> set[str]:
    """Declared member names of a type body."""
    names: set[str] = set()
    body = None
    for child in node.children:
        if child.type in ("class_body", "enum_class_body", "protocol_body"):
            body = child
            break
    if body is None:
        return names
    for child in body.named_children:
        if child.type == "property_declaration":
            pattern = None
            for sub in child.named_children:
                if sub.type == "pattern":
                    pattern = sub
                    break
            if pattern is not None:
                text = pattern.text.decode()
                text = text.split("=")[0].strip()
                if text and text.replace("_", "").isalnum():
                    names.add(text)
        elif child.type == "function_declaration":
            name = None
            for sub in child.children:
                if sub.type == "simple_identifier":
                    name = sub.text.decode()
                    break
            if name:
                names.add(name)
        elif child.type == "protocol_function_declaration":
            for sub in child.children:
                if sub.type == "simple_identifier":
                    names.add(sub.text.decode())
                    break
        elif child.type in ("enum_class_body",):
            for sub in child.named_children:
                if sub.type == "enum_element":
                    for leaf in sub.named_children:
                        if leaf.type == "identifier":
                            names.add(leaf.text.decode())
                            break
    return names


def walk(node):
    yield node
    for child in node.named_children:
        yield from walk(child)


# ---------------------------------------------------------------- index types
type_members: dict[str, set[str]] = {}
type_members.update({
    # members inherited from the Swift / Foundation / UIKit world that the
    # app uses but that are not declared in this repository.
    "String": {"count", "isEmpty", "uppercased", "lowercased", "trimmingCharacters",
               "hasPrefix", "hasSuffix", "contains", "split", "joined", "prefix",
               "suffix", "replacingOccurrences", "components", "append", "remove",
               "reversed", "sorted", "first", "last", "map", "filter", "reduce",
               "compactMap", "enumerated", "indices", "startIndex", "endIndex",
               "count", "isEmpty", "description", "debugDescription", "hashValue",
               "localizedCapitalized", "localizedLowercase", "capitalized",
               "compare", "range", "utf8", "utf16", "data", "base64EncodedString",
               "addingPercentEncoding", "removingPercentEncoding", "dropLast",
               "dropFirst", "prefix", "suffix", "replacingCharacters", "init",
               "lowercased", "capitalized", "contains", "trimmingCharacters",
               "split", "joined", "format", "padding", "count", "isEmpty",
               "unicodeScalars", "wholeNumberValue", "intValue", "doubleValue",
               "floatValue", "boolValue", "numberValue", "localizedString",
               "stringValue", "scoped", "appending", "removingLast"},
    "Int": {"description", "magnitude", "zero", "one", "max", "min",
            "addingReportingOverflow", "dividedReportingOverflow",
            "multipliedReportingOverflow", "subtractingReportingOverflow",
            "remainderReportingOverflow", "negated", "abs", "isMultiple",
            "random", "init", "description", "hashValue"},
    "Double": {"description", "isFinite", "isNaN", "isInfinite", "magnitude",
               "rounded", "rounded", "floor", "ceil", "truncatingRemainder",
               "addingReportingOverflow", "dividedReportingOverflow",
               "multipliedReportingOverflow", "subtractingReportingOverflow",
               "negated", "abs", "sign", "squareRoot", "init", "hashValue",
               "intValue", "rounded", "sign", "magnitude", "pi"},
    "Bool": {"description", "init", "hashValue"},
    "Date": {"description", "timeIntervalSinceNow", "timeIntervalSince",
             "timeIntervalSince1970", "addingTimeInterval", "formatted",
             "init", "distantPast", "distantFuture", "now", "hashValue",
             "timeIntervalSinceReferenceDate"},
    "URL": {"path", "lastPathComponent", "deletingLastPathComponent",
            "appendingPathComponent", "pathExtension", "absoluteString",
            "url", "resolvingSymlinksInPath", "standardizedFileURL",
            "filePathURL", "deletingPathExtension", "resourceValues"},
    "Data": {"count", "isEmpty", "append", "base64EncodedString", "count",
             "subscript", "withUnsafeBytes", "range", "description", "hashValue"},
    "UUID": {"uuidString", "description", "hashValue"},
    "Array": {"count", "isEmpty", "first", "last", "append", "append", "remove",
              "removeAll", "insert", "map", "filter", "reduce", "compactMap",
              "sorted", "sorted", "reversed", "enumerated", "indices", "joined",
              "contains", "removeLast", "removeFirst", "prefix", "suffix",
              "dropFirst", "dropLast", "shuffled", "max", "min", "flatMap",
              "forEach", "firstIndex", "index", "swapAt", "reverse", "sort"},
    "Dictionary": {"count", "isEmpty", "keys", "values", "removeValue",
                   "removeAll", "updateValue", "first", "filter", "map",
                   "forEach", "compactMap", "sorted", "description"},
    "Set": {"count", "isEmpty", "insert", "remove", "contains", "union",
            "intersection", "subtracting", "filter", "map", "forEach",
            "sorted", "first", "isSuperset", "formUnion"},
    "Optional": {"map", "flatMap", "ifPresent", "unwrapped", "description",
                 "isEmpty", "nil", "some"},
})

# ------------------------------------------------------------------- indexing
files: list[Path] = []
for directory in SEARCH_DIRS:
    if directory.exists():
        files.extend(sorted(directory.rglob("*.swift")))

for path in files:
    tree = parse(path)
    for node in walk(tree.root_node):
        if node.type not in DECL_TYPES:
            continue
        name = type_name_of(node)
        if not name:
            continue
        type_members.setdefault(name, set()).update(collect_members(node))

# ------------------------------------------------- local variables + accesses
VAR_TYPE = re.compile(
    r"(?:@[\w()\s,]*\s+)?(?:public\s+|private\s+|internal\s+|fileprivate\s+)?"
    r"(?:var|let)\s+([A-Za-z_]\w*)\s*(?::\s*([A-Za-z_][\w.]*))?"
    r"(?:\s*=\s*([A-Za-z_][\w.]*)\s*\()?"
)
ACCESS = re.compile(r"\b([A-Za-z_]\w*)\.([A-Za-z_]\w*)")

FRAMEWORK_TYPES = {
    "SwiftUI", "Foundation", "UIKit", "Combine", "CoreLocation", "MapKit",
    "CoreData", "CryptoKit", "AVFoundation", "PhotosUI", "Photos", "Security",
    "CoreGraphics", "CoreBluetooth", "Network", "LocalAuthentication", "Vision",
    "Speech", "WebKit", "UserNotifications", "WidgetKit", "SwiftData", "Charts",
    "ARKit", "SceneKit", "Metal", "MetalKit", "AVKit", "Contacts", "HealthKit",
    "CoreML", "NaturalLanguage", "OSLog", "UniformTypeIdentifiers", "BackgroundTasks",
    "PDFKit", "PencilKit", "MetricKit", "Intents", "AppIntents", "WidgetKit",
}

problems: list[str] = []
for path in files:
    src = path.read_text()
    tree = parse(path)
    locals_map: dict[str, str] = {}
    for node in walk(tree.root_node):
        if node.type != "property_declaration":
            continue
        text = node.text.decode()
        m = VAR_TYPE.search(text)
        if not m:
            continue
        name, declared, initializer = m.group(1), m.group(2), m.group(3)
        type_name = declared or initializer
        if not type_name or type_name in FRAMEWORK_TYPES:
            continue
        locals_map.setdefault(name, type_name)

    for node in walk(tree.root_node):
        if node.type != "navigation_expression":
            continue
        raw = node.text.decode()
        m = ACCESS.match(raw)
        if not m:
            continue
        receiver, member = m.group(1), m.group(2)
        type_name = locals_map.get(receiver)
        if not type_name:
            continue
        members = type_members.get(type_name)
        if members is None:
            continue
        if member in members:
            continue
        if member in ("self", "init", "Type", "some", "none"):
            continue
        problems.append(f"{path.relative_to(ROOT.parent)}: {receiver}.{member} -> {type_name} (line {node.start_point[0] + 1})")

seen = set()
print("=== possible missing members ===")
for problem in problems:
    if problem in seen:
        continue
    seen.add(problem)
    print("  " + problem)
print("total:", len(seen))
