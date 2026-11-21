#!/usr/bin/env python3
"""Checks that every localization carries the same keys and format specifiers.

A feature commit that adds a user-facing string must add it to every
`.lproj` in the same commit. When it does not, the app silently falls back to
English for that language, and the omission is easy to miss until someone
reads that language. The oversized-document placeholder, for example, shipped
in German and Simplified Chinese only, so Japanese, Polish and Persian readers
saw the English sentence for several commits.

The same commit can also break a translation by dropping or renumbering a
`%@` / `%1$@` placeholder; `String(format:)` then reads an argument that is
not there (or prints the wrong one). This script compares the specifiers of
each translated value with the English source.

Exit status is 1 when any key or placeholder differs, so CI can fail the PR.

Usage: python3 scripts/check-localizations.py [--root PROJECT_DIR]
"""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
from collections import Counter
from pathlib import Path

SOURCE_LANGUAGE = "en"

# A key may contain escaped quotes; a value may too. Lines outside a quoted
# pair (comments, blank lines) are ignored.
KEY_VALUE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)

# printf/NSString format specifiers, with optional positional index.
# Group 1 is the index, group 2 the specifier without it.
SPECIFIER = re.compile(
    r"%(?:(\d+)\$)?([-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dioufFeEgGxXcsSp%])"
)

# Files whose translations parallel the English source, per table.
TABLES = ("Localizable.strings", "MainMenu.strings")


def is_xml_plist(path: Path) -> bool:
    return path.read_bytes().lstrip().startswith(b"<?xml")


def read_strings(path: Path) -> dict[str, str]:
    """Returns the key/value pairs of a .strings file in either format."""
    if is_xml_plist(path):
        with path.open("rb") as handle:
            return {str(key): str(value) for key, value in plistlib.load(handle).items()}
    return {
        key: value
        for key, value in KEY_VALUE.findall(path.read_text(encoding="utf-8"))
    }


def duplicate_keys(path: Path) -> list[str]:
    """Keys repeated in a text-format .strings file.

    The last value wins, so a duplicate silently hides the first one. The
    same English word often appears in two UI contexts (the theme colour
    "Link" and the toolbar action "Link"); if those need different
    translations, they need different keys.
    """
    if is_xml_plist(path):
        return []
    counts = Counter(
        match.group(1)
        for match in KEY_VALUE.finditer(path.read_text(encoding="utf-8"))
    )
    return sorted(key for key, count in counts.items() if count > 1)


def specifiers(value: str) -> list[tuple[int, str]]:
    """The argument each format specifier consumes, sorted.

    `%d … %d` and `%1$d … %2$d` are the same instruction; %1$d and %2$d
    swapped consume the same two values in a different order. Normalise the
    implicit indexes to positional ones before comparing, and sort so a
    reordered translation does not look different.
    """
    consumed: list[tuple[int, str]] = []
    next_index = 1
    for match in SPECIFIER.finditer(value):
        token = match.group(2)
        if token == "%":  # a literal percent sign, not an argument
            continue
        index = int(match.group(1)) if match.group(1) else next_index
        if not match.group(1):
            next_index += 1
        consumed.append((index, token))
    return sorted(consumed)


def compare_table(table: str, languages: dict[str, dict[str, str]]) -> list[str]:
    problems: list[str] = []
    source = languages[SOURCE_LANGUAGE]
    for language, translations in languages.items():
        if language == SOURCE_LANGUAGE:
            continue
        missing = sorted(set(source) - set(translations))
        extra = sorted(set(translations) - set(source))
        for key in missing:
            problems.append(f"{table}: {language} is missing {key!r}")
        for key in extra:
            problems.append(f"{table}: {language} has a key English does not: {key!r}")
        for key in sorted(set(source) & set(translations)):
            expected = specifiers(source[key])
            actual = specifiers(translations[key])
            if expected != actual:
                problems.append(
                    f"{table}: {language} changed the placeholders of {key!r}: "
                    f"expected {expected}, found {actual}"
                )
    return problems


def localization_dirs(root: Path) -> list[Path]:
    # Base.lproj holds the unlocalized nibs, not a language.
    return sorted(
        path for path in root.glob("*.lproj")
        if path.is_dir() and path.stem != "Base"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("md-preview"),
                        help="directory containing the .lproj folders")
    args = parser.parse_args()

    dirs = localization_dirs(args.root)
    languages = {path.stem: path for path in dirs}
    if SOURCE_LANGUAGE not in languages:
        print(f"No {SOURCE_LANGUAGE}.lproj under {args.root}", file=sys.stderr)
        return 2

    problems: list[str] = []
    for table in TABLES:
        files = {
            language: path / table
            for language, path in languages.items()
            if (path / table).is_file()
        }
        if SOURCE_LANGUAGE not in files:
            continue
        loaded = {language: read_strings(path) for language, path in files.items()}
        missing_table = sorted(set(languages) - set(files))
        for language in missing_table:
            problems.append(f"{table}: {language} has no {table}")
        for language, path in files.items():
            for key in duplicate_keys(path):
                problems.append(f"{table}: {language} repeats {key!r}")
        problems.extend(compare_table(table, loaded))

    if problems:
        print("Localization checks failed:")
        for problem in problems:
            print(f"- {problem}")
        return 1

    checked = ", ".join(sorted(languages))
    print(f"Localization checks passed ({checked}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
