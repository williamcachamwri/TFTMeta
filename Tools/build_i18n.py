#!/usr/bin/env python3
"""Compile the strings the app actually references into App/Resources/i18n.json.

Call sites are `L("MetaTrends.winRate")` — a key from op.gg's catalogue, harvested next door by
harvest_i18n.py — or `L("App.hexOdds", ...)`, a string the reference has no equivalent for, which
lives in Tools/i18n/app.json. Scanning the sources instead of keeping a manifest means the
generated table can never carry a dead key, and a typo fails the build rather than showing the
key on screen.

Usage (from the repo root): python3 Tools/build_i18n.py
"""

import glob
import json
import re
import sys

LOCALES = ["vi", "en", "ko", "ja", "zh-tw"]
# ICU plural/select blocks and inline markup need a real formatter to render; this app only does
# positional substitution, so those keys are rejected until someone rewrites them by hand.
UNSUPPORTED = re.compile(r",\s*(plural|select)\s*,|<\s*/?\s*[A-Za-z]")
USAGE = re.compile(r'(?<![A-Za-z0-9_])(L(?:Cap|Plural|Split)?)\("([^"]+)"')
# A call site that builds its key by interpolation (`L("Region.name@\(code)")`) names the branch
# family it draws from, so the table can still carry every member of it.
PREFIX = re.compile(r"@i18n\s+([\w.@-]+)")
ICU_HEAD = re.compile(r"^\{\s*\w+\s*,\s*(?:plural|select)\s*,")
ICU_BLOCK = re.compile(r"\{\s*\w+\s*,\s*(?:plural|select)\s*,")


def branches(text):
    """`{var, select, na {North America} kr {한국}}` → [("na", "North America"), …].

    op.gg keeps the lists the app has to localise — server names, league tiers, combat roles —
    inside ICU select blocks instead of separate keys. Splitting them here means the app gets the
    reference's own wording for every entry rather than a translation of it.
    """
    if not ICU_HEAD.match(text):
        return []
    out, depth, name, body, pending = [], 0, None, "", ""
    # Step past `{var, select,` or `{var, plural,`
    head = ICU_HEAD.match(text).end()
    while head < len(text):
        character = text[head]
        if depth == 0:
            if character.isspace():
                head += 1
                continue
            if character == "=" or character.isalnum() or character == "_":
                pending += character
            elif character == "{":
                if pending:
                    name = pending.split()[0]  # `=5 {…}` and `other {…}` both key on the first word
                    pending = ""
                depth = 1
            elif character == "}":
                break
            head += 1
            continue
        if character == "{":
            depth += 1
            if depth > 1:
                body += character
        elif character == "}":
            depth -= 1
            if depth == 0:
                out.append((name, body.strip()))
                body, name = "", None
            else:
                body += character
        else:
            body += character
        head += 1
    return out


def explode(catalogue):
    """Add `key@branch` entries for every flat ICU block in the catalogue."""
    extra = {}
    for key, text in catalogue.items():
        if not isinstance(text, str):
            continue
        # A message mixing prose with more than one block ("# thắng / # thua ({rate}%)") is a
        # template, not a list: splitting it would hand the app half a sentence.
        if len(ICU_BLOCK.findall(text)) != 1:
            continue
        parsed = branches(text)
        if not parsed:
            continue
        if any(UNSUPPORTED.search(value) for _, value in parsed):
            continue
        for name, value in parsed:
            if not value:
                continue
            if name.isdigit():
                name = "=%s" % name
            extra[f"{key}@{name}"] = value
    return extra


def load(name):
    with open(f"Tools/i18n/{name}.json", encoding="utf-8") as handle:
        return json.load(handle)


def main():
    catalogue = {}
    for locale in LOCALES:
        base = load(locale)
        merged = dict(base)
        merged.update(explode(base))
        catalogue[locale] = merged
    with open("Tools/i18n/app.json", encoding="utf-8") as handle:
        custom = json.load(handle)
    # A greppable index of everything the app can ask for, so picking a key is one search instead
    # of a python round-trip.
    with open("Tools/i18n/index.tsv", "w", encoding="utf-8") as handle:
        for key in sorted(set(catalogue["vi"]) | set(custom)):
            entry = custom.get(key) or {locale: catalogue[locale].get(key, "") for locale in LOCALES}
            handle.write(key + "\t" + "\t".join(entry.get(locale, "") for locale in LOCALES) + "\n")

    used = {}
    plural_keys = set()
    for path in sorted(glob.glob("App/**/*.swift", recursive=True)):
        if path.endswith("L10n.swift"):
            continue
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
            for func_name, key in USAGE.findall(source):
                if "\\(" in key:
                    continue  # dynamic — declared with `@i18n` below
                used.setdefault(key, []).append(path)
                if func_name == "LPlural":
                    plural_keys.add(key)
            for family in PREFIX.findall(source):
                for key in catalogue["vi"]:
                    if key.startswith(family):
                        used.setdefault(key, []).append(path)

    table = {}
    problems = []
    for key in sorted(used):
        entry = custom[key] if key in custom else {l: catalogue[l].get(key) for l in LOCALES}
        missing = [locale for locale in LOCALES if not entry.get(locale)]
        if len(missing) == len(LOCALES):
            problems.append(f"unknown key {key}  ({used[key][0]})")
            continue
        if missing:
            problems.append(f"key {key} has no text in {missing}")
            continue
        # Plural keys are expected to have ICU markup — they're handled by LPlural() at runtime.
        if key not in plural_keys:
            shaped = [locale for locale in LOCALES if UNSUPPORTED.search(entry[locale])]
            if shaped:
                problems.append(f"key {key} needs ICU or markup handling ({shaped})")
                continue
        table[key] = {locale: entry[locale] for locale in LOCALES}

    if problems:
        for line in problems:
            print(line)
        return 1

    with open("App/Resources/i18n.json", "w", encoding="utf-8") as handle:
        json.dump(table, handle, ensure_ascii=False, indent=1, sort_keys=True)
    print(f"{len(table)} keys -> App/Resources/i18n.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
