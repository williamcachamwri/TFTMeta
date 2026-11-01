#!/usr/bin/env python3
"""Look up a Vietnamese UI string in op.gg's catalogue and print the keys it maps to.

Rewriting a label means choosing a key, and several keys share the same Vietnamese text
("Đội hình" is a nav item, a table header and a filter). This prints every candidate with all
five translations side by side so the choice is made with the answer visible.

Usage: python3 Tools/lookup.py "Đội hình" "Tỉ lệ thắng" …
"""

import json
import sys

LOCALES = ["vi", "en", "ko", "ja", "zh-tw"]


def main():
    catalogue = {}
    for locale in LOCALES:
        with open(f"Tools/i18n/{locale}.json", encoding="utf-8") as handle:
            catalogue[locale] = json.load(handle)

    for wanted in sys.argv[1:]:
        matches = [key for key, text in catalogue["vi"].items()
                   if isinstance(text, str) and text.strip() == wanted]
        if not matches:
            loose = [key for key, text in catalogue["vi"].items()
                     if isinstance(text, str) and wanted.lower() in text.lower()][:6]
            print(f"== {wanted!r}: no exact key. loose: {loose}")
            continue
        print(f"== {wanted!r}")
        for key in sorted(matches):
            parts = " | ".join(f"{locale} {str(catalogue[locale][key])[:42]}" for locale in LOCALES[1:])
            shape = " [ICU/markup]" if any(
                "{" in str(catalogue[locale][key]) or "<" in str(catalogue[locale][key])
                for locale in LOCALES) else ""
            print(f"   {key}{shape}  {parts}")


if __name__ == "__main__":
    main()
