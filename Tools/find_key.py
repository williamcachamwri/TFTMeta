#!/usr/bin/env python3
"""Find the catalogue key for a label the app currently hardcodes.

Reads Tools/i18n/index.tsv (written by build_i18n.py) and prints every row whose Vietnamese,
English or key matches, so a rewrite picks op.gg's own words instead of inventing a translation.

Usage: python3 Tools/find_key.py exact "Tầm đánh"        # whole-value match
       python3 Tools/find_key.py re "chí mạng|crit"       # substring / regex over vi text and keys
"""

import sys

LOCALES = ["vi", "en", "ko", "ja", "zh-tw"]


def rows():
    with open("Tools/i18n/index.tsv", encoding="utf-8") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 1 + len(LOCALES):
                yield dict(zip(["key"] + LOCALES, parts))


def main():
    import re

    mode, patterns = sys.argv[1], sys.argv[2:]
    for pattern in patterns:
        print("== %s" % pattern)
        rx = re.compile(pattern, re.I) if mode == "re" else None
        shown = 0
        for row in rows():
            hit = (row["vi"] == pattern) if mode == "exact" else bool(
                rx.search(row["vi"]) or rx.search(row["en"]) or rx.search(row["key"]))
            if not hit:
                continue
            shown += 1
            if shown > 20:
                print("   ...")
                break
            print("   %-44s vi %-24s en %-22s ko %-12s ja %-12s zh %s" %
                  (row["key"], row["vi"][:24], row["en"][:22], row["ko"][:12], row["ja"][:12], row["zh-tw"][:12]))
        if not shown:
            print("   (no match)")


if __name__ == "__main__":
    main()
