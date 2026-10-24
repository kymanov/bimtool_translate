#!/usr/bin/env python3
"""Extract German UI strings from a BMWTOOL binary/installer into a bilingual
translation file (de -> target) for machine/human translation.

Usage:
    python3 -I scripts/extract_strings.py <path-to-exe-or-dll> [-o i18n/translations.de.json]

Notes:
- Reads UTF-16LE strings (standard for Win32 resource text). Pass --ascii too
  for byte strings. The source installer stores most UI text inside a compressed
  payload; run this against the *installed* .exe/.dll files for the full set.
- Output schema: {"meta": {...}, "strings": [{"id","de","target","context"}]}
"""
import argparse
import json
import os
import re
import sys

UML = re.compile(r"[äöüÄÖÜß]")
GKW = re.compile(
    r"\b(der|die|das|und|nicht|Datei|Fehler|Einstellung|Schlüssel|wählen|"
    r"Abbrechen|Speichern|Laden|Löschen|Zurück|Weiter|Drucken|Verbindung|"
    r"erfolgreich|ungültig|Bitte|Programm|Hilfe|Beenden|öffnen|schließen|"
    r"Fahrzeug|Steuergerät|aktiv|Daten|Taste|drücken|geben|werden|wurde|keine|muss)\b",
    re.I,
)


def iter_utf16le(data: bytes, min_len: int):
    """Yield printable UTF-16LE runs of at least min_len characters."""
    out = []
    i, n = 0, len(data) - 1
    while i < n:
        lo, hi = data[i], data[i + 1]
        if hi == 0 and (32 <= lo < 127 or lo in (9,)):
            out.append(chr(lo))
            i += 2
        elif hi in (0x00, 0x20) and lo >= 0x20:  # keep latin-1 incl. umlauts area
            try:
                ch = bytes([lo, hi]).decode("utf-16-le")
                if ch.isprintable():
                    out.append(ch)
                    i += 2
                    continue
            except Exception:
                pass
            if len(out) >= min_len:
                yield "".join(out)
            out = []
            i += 2
        else:
            if len(out) >= min_len:
                yield "".join(out)
            out = []
            i += 2
    if len(out) >= min_len:
        yield "".join(out)


def is_german_ui(s: str) -> bool:
    s = s.strip()
    if not (3 <= len(s) <= 200):
        return False
    if not re.search(r"[A-Za-zÀ-ÿ]", s):
        return False
    if re.search(r"[\\/]{2}", s):  # skip path-like noise
        return False
    return bool(UML.search(s) or GKW.search(s))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="binary to scan (.exe/.dll) or installer")
    ap.add_argument("-o", "--out", default="i18n/translations.de.json")
    ap.add_argument("--min-len", type=int, default=3)
    ap.add_argument("--target-lang", default="")
    args = ap.parse_args()

    with open(args.path, "rb") as f:
        data = f.read()

    seen = {}
    for s in iter_utf16le(data, args.min_len):
        s = s.strip()
        if is_german_ui(s):
            seen.setdefault(s, None)

    items = sorted(seen)
    doc = {
        "meta": {
            "source": os.path.basename(args.path),
            "encoding": "utf-16le",
            "source_lang": "de",
            "target_lang": args.target_lang,
            "count": len(items),
            "note": "Fill the 'target' field per entry with another model, then "
            "merge back. Strings from a packed installer are partial; scan the "
            "installed app binaries for the complete set.",
        },
        "strings": [
            {"id": f"s{idx:04d}", "de": s, "target": "", "context": ""}
            for idx, s in enumerate(items, 1)
        ],
    }
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as o:
        json.dump(doc, o, ensure_ascii=False, indent=2)
    print(f"extracted {len(items)} German strings -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
