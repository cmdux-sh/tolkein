#!/usr/bin/env python3
"""Pick the Swift test suites a pull request needs, from its changed paths.

Prints one suite name per line (the test struct or class name), or the single line ALL when the change is broad
enough that the whole suite should run. Pushes to main always run everything; this only narrows pull requests.

A suite is selected when:
- its test file changed, or
- its test file mentions a type, extension or top-level function declared in a changed Swift source file.

Usage: ci_select_test_suites.py <changed-paths-file> [--repo <root>]
The changed-paths file is `git diff --name-status` output (status, tab, path; renames list both paths).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ALL = "ALL"

# Changes here can affect any test: build setup, the test runners and shared test helpers.
BROAD_PREFIXES = (
    "Package.swift",
    "Package.resolved",
    "Scripts/test",
    "Scripts/run_swift_test.py",
    "Scripts/ci_swift_test_by_suite.py",
    "Scripts/direct_swift_test_groups.py",
    "Scripts/ci_select_test_suites.py",
    ".github/workflows/",
)
TEST_ROOT = "Tests/"
SOURCE_ROOT = "Sources/"
# A test file that declares no suite of its own (fixtures, helpers) is shared, so changing it runs everything.
# Names other files can use: top-level declarations that are not private, and the members an extension adds (one
# level in). Nested types and private helpers are left out; their names are too common to narrow anything.
MODIFIERS = r"(?:(?:public|internal|package|final|open|nonisolated|static|override|@MainActor|@objc)\s+)*"
TOP_LEVEL = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s+)*" + MODIFIERS + r"(struct|class|enum|actor|protocol|extension|typealias|func)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
EXTENSION_MEMBER = re.compile(
    r"^    (?:@\w+(?:\([^)]*\))?\s+)*" + MODIFIERS + r"(?:func|var|let|struct|class|enum)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
EXTENSION_BLOCK = re.compile(r"^extension\s+[^\n{]*\{\n(.*?)^\}", re.MULTILINE | re.DOTALL)
SUITE = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:final\s+)?(?:struct|class)\s+([A-Za-z_][A-Za-z0-9_]*Tests)\b",
                   re.MULTILINE)
# Too general to narrow anything: almost every test mentions them.
GENERIC_NAMES = {"View", "String", "Int", "Bool", "Date", "URL", "Data", "Error", "Equatable", "Hashable", "Codable",
                 "Sendable", "Identifiable", "body", "init", "main", "L"}
# Above this share of all suites, running everything is simpler and costs little more.
MAX_SHARE = 0.6
# A member name used in more than this share of test files is treated as too common to select by.
MEMBER_SHARE = 0.05


def changed_paths(changes_file: Path) -> list[str]:
    paths: list[str] = []
    for line in changes_file.read_text().splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            paths.extend(part for part in parts[1:] if part)
    return paths


def declared_names(source: str) -> set[str]:
    names = {name for kind, name in TOP_LEVEL.findall(source) if kind != "extension"}
    for block in EXTENSION_BLOCK.findall(source):
        names.update(EXTENSION_MEMBER.findall(block))
    return {name for name in names if name not in GENERIC_NAMES and len(name) > 2}


def suites_in(source: str) -> list[str]:
    return SUITE.findall(source)


def select(paths: list[str], repo: Path) -> list[str] | None:
    """The suites to run, or None for all of them."""
    if any(path.startswith(BROAD_PREFIXES) for path in paths):
        return None

    test_files = {path: path_text(repo / path) for path in tracked_test_files(repo)}
    all_suites = {suite for text in test_files.values() for suite in suites_in(text)}
    selected: set[str] = set()
    names: set[str] = set()

    for path in paths:
        if not path.endswith(".swift"):
            continue
        if path.startswith(TEST_ROOT):
            text = test_files.get(path) or path_text(repo / path)
            found = suites_in(text)
            if text and not found:
                return None  # a shared test helper changed
            selected.update(found)
            if not text:  # deleted test file: nothing left to run for it
                continue
        elif path.startswith(SOURCE_ROOT):
            text = path_text(repo / path)
            names |= declared_names(text) if text else {Path(path).stem.split("+")[0]}

    # A member name (lowercase) that most tests happen to use, such as `label`, narrows nothing; types always count.
    common = {name for name in names if name[0].islower()
              and sum(1 for text in test_files.values() if re.search(rf"\b{re.escape(name)}\b", text))
              > MEMBER_SHARE * len(test_files)}
    names -= common
    if names:
        pattern = re.compile(r"\b(?:" + "|".join(sorted(map(re.escape, names))) + r")\b")
        for text in test_files.values():
            if pattern.search(text):
                selected.update(suites_in(text))

    if all_suites and len(selected) > MAX_SHARE * len(all_suites):
        return None
    return sorted(selected)


def tracked_test_files(repo: Path) -> list[str]:
    return sorted(str(path.relative_to(repo)) for path in (repo / TEST_ROOT).rglob("*.swift"))


def path_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (FileNotFoundError, UnicodeDecodeError):
        return ""


def self_test() -> None:
    source = (
        "struct Foo {\n    enum Section {}\n}\n"
        "extension Bar: View {\n    func quux() {}\n    private func hidden() {}\n    var body: some View {}\n}\n"
        "private func baz() {}\n"
    )
    assert declared_names(source) == {"Foo", "quux"}, declared_names(source)
    assert declared_names("@MainActor\nfinal class SettingsStore {}") == {"SettingsStore"}
    assert suites_in("@MainActor\n@Suite(.serialized)\nstruct FooTests {}\nstruct Helper {}") == ["FooTests"]
    assert changed_paths_from_lines(["M\tSources/A.swift", "R100\tOld.swift\tNew.swift"]) == [
        "Sources/A.swift", "Old.swift", "New.swift"]
    print("test suite selector tests OK")


def changed_paths_from_lines(lines: list[str]) -> list[str]:
    paths: list[str] = []
    for line in lines:
        parts = line.split("\t")
        paths.extend(part for part in parts[1:] if part)
    return paths


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("changes", nargs="?", type=Path)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--test", action="store_true", help="run the selector's own checks")
    args = parser.parse_args()
    if args.test:
        self_test()
        return 0
    if args.changes is None:
        parser.error("the changed-paths file is required")
    suites = select(changed_paths(args.changes), args.repo)
    if suites is None:
        print(ALL)
    else:
        print("\n".join(suites))
    return 0


if __name__ == "__main__":
    sys.exit(main())
