#!/usr/bin/env python3
"""Re-harvest op.gg's own translation catalogues into Tools/i18n/<locale>.json.

The app's UI strings are op.gg's UI strings, so the reference's message catalogue is the
dictionary: 1,331 keys, present in all five locales the site renders. Each page embeds the whole
catalogue for its own locale inside a Next.js flight chunk, escaped as a JS string literal — the
unescape-and-brace-walk below is what lifts it out.

Run this after op.gg ships a new set (or renames a stat) so build_i18n.py has fresh terminology.
"""

import json
import sys
import urllib.request

LOCALES = ["vi", "en", "ko", "ja", "zh-tw"]
PAGE = "/tft/meta-trends/comps?version=18.5"
# Any stable key works as the entry point into the catalogue object; winRate is on every page.
ANCHOR = '"winRate":"'
USER_AGENT = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
              "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")


def flight_text(url, locale):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept-Language": locale})
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read().decode("utf-8", "ignore")


def outermost_object(text, anchor):
    """Walk backwards from the anchor to the first `{` that nothing closes on its left."""
    found = text.find(anchor)
    if found < 0:
        raise SystemExit(f"anchor {anchor} not in payload")
    depth, start = 0, None
    for index in range(found, -1, -1):
        character = text[index]
        if character == "}":
            depth += 1
        elif character == "{":
            if depth == 0:
                start = index
            else:
                depth -= 1
    if start is None:
        raise SystemExit("no enclosing object")
    return json.JSONDecoder().raw_decode(text[start:])[0]


def flatten(messages, prefix=""):
    out = {}
    for key, value in messages.items():
        if isinstance(value, dict):
            out.update(flatten(value, f"{prefix}{key}."))
        else:
            out[f"{prefix}{key}"] = value
    return out


def main():
    for locale in LOCALES:
        origin = "https://op.gg" if locale == "en" else f"https://op.gg/{locale}"
        raw = flight_text(origin + PAGE, locale)
        payload = outermost_object(raw.replace('\\"', '"'), ANCHOR)
        flat = flatten(payload["messages"])
        with open(f"i18n/{locale}.json", "w", encoding="utf-8") as handle:
            json.dump(flat, handle, ensure_ascii=False, indent=1, sort_keys=True)
        print(locale, len(flat), "keys")
    return 0


if __name__ == "__main__":
    sys.exit(main())
