#!/usr/bin/env python3
"""Extract German UI strings from VVDI2 BMW TOOL's language resource
(BMW_Language.dll) into a bilingual translation file (de -> target).

The DLL holds a serialized multilingual string table: a flat sequence of
length-prefixed UTF-16LE strings (uint16 character count, little-endian,
followed by count*2 bytes). Translations for every supported language
(German, English, Spanish, Italian, Polish, Hungarian, Danish, Chinese, ...)
are interleaved, so we parse all strings and keep the German ones.

Usage:
    python3 -I scripts/extract_strings.py "/path/to/BMW_Language.dll" \
        -o i18n/translations.de.json --csv i18n/translations.de.csv
"""
import argparse
import csv
import json
import os
import re
import sys

# German-specific (ä/ß never appear in Hungarian, the main false-positive source)
DE_SPECIFIC = re.compile(r"[äßÄ]")
DE_KW = re.compile(
    r"\b(der|die|das|und|nicht|Datei|Fehler|Einstellung\w*|Schlüssel|wählen|"
    r"Abbrechen|Speichern|Laden|Löschen|Zurück|Weiter|Drucken|Verbindung|"
    r"erfolgreich|ungültig|Bitte|Programm\w*|Hilfe|Beenden|öffnen|schließen|"
    r"Fahrzeug|Steuergerät|Taste|drücken|wurde|keine|muss|Wert|Daten|neue\w*|"
    r"bereit|Schreib\w*|ist|ein|eine|werden|haben|Sie|gefunden|gelesen|"
    r"geschrieben|gespeichert|geladen)\b"
)
# other-language markers to exclude (they share ö/ü with German)
EXCLUDE = [
    re.compile(r"[őűŐŰ]|\b(az|egy|meg|hogy|és|nem|kulcs|eszköz|autó|gomb|fájl|"
               r"Nyomd|Töltsd|sikeres|sikertelen|vagy|van|lesz|betöltése)\b"),  # HU
    re.compile(r"[ąęłżźśćńĄĘŁŻŹŚĆŃ]|\b(nie|klucz|plik|przycisk|wczytaj|Naciśnij)\b"),  # PL
    re.compile(r"[ñ¿¡]|\b(archivo|clave|llave|botón|presione|Cargar|éxito|programador)\b"),  # ES
    re.compile(r"\b(chiave|file|pulsante|strumento|premere|successo|caricare|nuovo)\b"),  # IT
    re.compile(r"\b(på|til|med|ikke|nøgle|fil|knap|Tryk|indlæs|gemt)\b"),  # DA
]


def is_clean(s: str) -> bool:
    if not s or s.isspace():
        return False
    for c in s:
        if ("　" <= c <= "鿿" or "가" <= c <= "퟿"
                or "぀" <= c <= "ヿ" or "" <= c <= ""):
            return False  # CJK / Hangul / Kana / PUA => misaligned read
    return all(c.isprintable() or c in "\t\r\n" for c in s)


def parse_table(data: bytes):
    n, i = len(data), 0
    while i < n - 2:
        ln = data[i] | (data[i + 1] << 8)
        if 1 <= ln <= 2000 and i + 2 + ln * 2 <= n:
            try:
                s = data[i + 2:i + 2 + ln * 2].decode("utf-16-le")
            except Exception:
                i += 1
                continue
            if is_clean(s):
                yield s
                i += 2 + ln * 2
                continue
        i += 1


def is_german(t: str) -> bool:
    if not (2 <= len(t) <= 400):
        return False
    if any(rx.search(t) for rx in EXCLUDE):
        return False
    return bool(
        DE_SPECIFIC.search(t)
        or len(DE_KW.findall(t)) >= 2
        or (len(DE_KW.findall(t)) >= 1 and ("ü" in t or "ö" in t))
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="BMW_Language.dll (or similar language resource)")
    ap.add_argument("-o", "--out", default="i18n/translations.de.json")
    ap.add_argument("--csv", default="")
    ap.add_argument("--target-lang", default="")
    args = ap.parse_args()

    with open(args.path, "rb") as f:
        data = f.read()

    seen, de = set(), []
    for s in parse_table(data):
        t = s.replace("\x00", "").strip()
        if is_german(t) and t not in seen:
            seen.add(t)
            de.append(t)

    doc = {
        "meta": {
            "source": os.path.basename(args.path),
            "app": "VVDI2 BMW TOOL",
            "encoding": "utf-16le length-prefixed string table",
            "source_lang": "de",
            "target_lang": args.target_lang,
            "count": len(de),
            "note": "Fill each 'target' with a translation model, then merge back "
                    "into the app's language resource.",
        },
        "strings": [
            {"id": f"s{i:04d}", "de": t, "target": "", "context": ""}
            for i, t in enumerate(de, 1)
        ],
    }
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as o:
        json.dump(doc, o, ensure_ascii=False, indent=2)
    if args.csv:
        with open(args.csv, "w", encoding="utf-8-sig", newline="") as o:
            w = csv.writer(o)
            w.writerow(["id", "de", "target"])
            for i, t in enumerate(de, 1):
                w.writerow([f"s{i:04d}", t, ""])
    print(f"extracted {len(de)} German strings -> {args.out}"
          + (f" + {args.csv}" if args.csv else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
