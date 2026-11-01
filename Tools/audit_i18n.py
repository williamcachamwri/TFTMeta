#!/usr/bin/env python3
"""List the Vietnamese UI strings still hardcoded in the sources.

The language pass is done when this prints nothing: every label on screen should come from
`L("…")`, and a literal left in place is a label that will stay Vietnamese after a switch.
Comments are stripped, so only strings that reach the UI are reported.

Usage (from the repo root): python3 Tools/audit_i18n.py
"""

import glob
import re
import sys
import unicodedata

COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/", re.DOTALL)
STRING = re.compile(r'"(?:[^"\\]|\\.)*"')


def is_accented(character):
    """A Latin letter carrying a mark, or Vietnamese's đ — the app has no other accented UI."""
    if character in "đĐ":
        return True
    return character.isalpha() and unicodedata.normalize("NFD", character) != character


def has_vietnamese(text):
    return any(is_accented(character) for character in text)


def main():
    total = 0
    for path in sorted(glob.glob("App/**/*.swift", recursive=True)):
        if path.endswith("L10n.swift") or path.endswith("AppLanguage.swift"):
            continue
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        lines = COMMENT.sub(lambda match: re.sub(r"[^\n]", " ", match.group(0)), source).split("\n")
        hits = []
        for number, line in enumerate(lines, start=1):
            for literal in STRING.findall(line):
                if has_vietnamese(literal):
                    hits.append((number, literal[:78]))
        if hits:
            print(f"--- {path} ({len(hits)})")
            for number, literal in hits:
                print(f"  {number:5d}  {literal}")
            total += len(hits)
    print(f"{total} hardcoded strings left")
    return 0


if __name__ == "__main__":
    sys.exit(main())
