#!/usr/bin/env python3
"""Register the Swift sources of the Resilix app in the Xcode project.

The project uses a classic `project.pbxproj` (objectVersion 56) with a flat
group per target, so every new source file needs four entries:

* a `PBXFileReference`,
* a `PBXBuildFile`,
* a child entry in the target group,
* an entry in the `PBXSourcesBuildPhase` of the target.

The script adds the missing files and removes the entries of files that were
deleted from the disk.
"""
from __future__ import annotations

import hashlib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECT = ROOT / "Resilix.xcodeproj" / "project.pbxproj"

APP_GROUP = "4A28A448D526473EB9CE4AD1"      # group "Resilix"
TEST_GROUP = "A1B2C3D4E5F60718293A4B5C"     # group "ResilixTests" (looked up below)
APP_SOURCES = "84CCD72FD41F4315B1EAA070"
TEST_SOURCES = "0CC2FA91197C44C38EA94356"


def used_ids(text: str) -> set[str]:
    return set(re.findall(r"\b[0-9A-F]{24}\b", text))


def make_id(seed: str, taken: set[str]) -> str:
    counter = 0
    while True:
        digest = hashlib.sha1(f"{seed}-{counter}".encode()).hexdigest().upper()[:24]
        if digest not in taken:
            taken.add(digest)
            return digest
        counter += 1


def group_id_for(path_text: str, group_name: str) -> str | None:
    """Returns the id of the PBXGroup whose `name`/`path` matches."""
    pattern = re.compile(
        r"\t\t([0-9A-F]{24}) /\* %s \*/ = \{\n\t\t\tisa = PBXGroup;.*?\n\t\t\};" % group_name,
        re.S,
    )
    match = pattern.search(path_text)
    return match.group(1) if match else None


def file_references(text: str) -> dict[str, str]:
    """Maps `path` -> file reference id (only group relative files)."""
    result: dict[str, str] = {}
    pattern = re.compile(
        r"\t\t([0-9A-F]{24}) /\* .*? \*/ = \{isa = PBXFileReference;(?P<body>[^\n]*)\n"
    )
    for match in pattern.finditer(text):
        line = match.group(0)
        if "BUILT_PRODUCTS_DIR" in line or "SDKROOT" in line or "DEVELOPER_DIR" in line:
            # Build products are not files inside the repository.
            continue
        path_match = re.search(r"path = ([^;]+);", line)
        if not path_match:
            continue
        result[path_match.group(1).strip('"')] = match.group(1)
    return result


def remove_entries(text: str, paths: list[str]) -> str:
    for path in paths:
        # PBXBuildFile entry
        text = re.sub(
            r"\t\t[0-9A-F]{24} /\* %s in Sources \*/ = \{isa = PBXBuildFile;[^\n]*\n" % re.escape(path),
            "",
            text,
        )
        # PBXFileReference entry
        text = re.sub(
            r"\t\t[0-9A-F]{24} /\* %s \*/ = \{isa = PBXFileReference;[^\n]*\n" % re.escape(path),
            "",
            text,
        )
        # group child
        text = re.sub(
            r"\t\t\t\t[0-9A-F]{24} /\* %s \*/,\n" % re.escape(path), "", text
        )
        # sources build phase
        text = re.sub(
            r"\t\t\t\t[0-9A-F]{24} /\* %s in Sources \*/,\n" % re.escape(path), "", text
        )
    return text


def add_to_section(text: str, section: str, entry: str) -> str:
    """Inserts `entry` at the end of the given PBX section."""
    marker = f"/* Begin {section} section */"
    end_marker = f"/* End {section} section */"
    start = text.index(marker) + len(marker)
    end = text.index(end_marker)
    block = text[start:end]
    if not block.endswith("\n"):
        block += "\n"
    block += entry
    return text[:start] + block + text[end:]


def add_group_child(text: str, group_id: str, entry: str) -> str:
    pattern = re.compile(
        r"(\t\t%s /\* .*? \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)" % group_id
    )
    match = pattern.search(text)
    if not match:
        raise SystemExit(f"group {group_id} not found")
    return text[: match.end(1)] + entry + text[match.end(1):]


def add_phase_file(text: str, phase_id: str, entry: str) -> str:
    pattern = re.compile(
        r"(\t\t%s /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = \(\n)"
        % phase_id
    )
    match = pattern.search(text)
    if not match:
        raise SystemExit(f"sources phase {phase_id} not found")
    return text[: match.end(1)] + entry + text[match.end(1):]


def main() -> int:
    text = PROJECT.read_text()
    taken = used_ids(text)

    app_group = group_id_for(text, "Resilix")
    test_group = group_id_for(text, "ResilixTests")
    if app_group is None or test_group is None:
        raise SystemExit("target groups not found")

    referenced = file_references(text)
    # Paths of the test target are relative to the "ResilixTests" group.
    test_referenced = {path for path in referenced if path in
                       {str(p.relative_to(ROOT / "ResilixTests")) for p in (ROOT / "ResilixTests").rglob("*.swift")}}

    # ---------------------------------------------------------------- remove
    removed = []
    for path, _id in list(referenced.items()):
        if path in test_referenced:
            absolute = ROOT / "ResilixTests" / path
        else:
            absolute = ROOT / "Resilix" / path if not path.startswith("Resilix/") else ROOT / path
        if not absolute.exists():
            removed.append(path)
    if removed:
        text = remove_entries(text, removed)

    # ------------------------------------------------------------------ add
    app_sources = sorted(
        str(p.relative_to(ROOT / "Resilix")) for p in (ROOT / "Resilix").rglob("*.swift")
    )
    test_sources = sorted(
        str(p.relative_to(ROOT / "ResilixTests")) for p in (ROOT / "ResilixTests").rglob("*.swift")
    )

    added = []
    for relative in app_sources:
        if relative in referenced:
            continue
        file_ref = make_id(f"file:{relative}", taken)
        build_file = make_id(f"build:{relative}", taken)
        text = add_to_section(
            text,
            "PBXBuildFile",
            f"\t\t{build_file} /* {relative} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {relative} */; }};\n",
        )
        text = add_to_section(
            text,
            "PBXFileReference",
            f"\t\t{file_ref} /* {relative} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {relative}; sourceTree = \"<group>\"; }};\n",
        )
        text = add_group_child(text, app_group, f"\t\t\t\t{file_ref} /* {relative} */,\n")
        text = add_phase_file(text, APP_SOURCES, f"\t\t\t\t{build_file} /* {relative} in Sources */,\n")
        added.append(relative)

    for relative in test_sources:
        if relative in referenced:
            continue
        file_ref = make_id(f"testfile:{relative}", taken)
        build_file = make_id(f"testbuild:{relative}", taken)
        text = add_to_section(
            text,
            "PBXBuildFile",
            f"\t\t{build_file} /* {relative} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {relative} */; }};\n",
        )
        text = add_to_section(
            text,
            "PBXFileReference",
            f"\t\t{file_ref} /* {relative} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {relative}; sourceTree = \"<group>\"; }};\n",
        )
        text = add_group_child(text, test_group, f"\t\t\t\t{file_ref} /* {relative} */,\n")
        text = add_phase_file(text, TEST_SOURCES, f"\t\t\t\t{build_file} /* {relative} in Sources */,\n")
        added.append(relative)

    PROJECT.write_text(text)
    print(f"removed: {removed}")
    print(f"added: {len(added)}")
    for path in added:
        print(f"  + {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
