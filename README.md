# bimtool_translate

German → target-language translation project for the BMWTOOL application
(installer: `BMWTOOL-InstallerV188.exe`, v1.8.8).

The goal: understand the application, extract its German UI strings, and produce
a **bilingual translation file** (`de` → `target`) that another model can fill
in, then merge back into the app.

> The proprietary installer binary is **not** committed (copyrighted, ~448 MB).

## Reverse-engineering findings

Analyzed with Ruflo's static RE tools (`rure_analyze_binary`) — the file is
never executed.

| Layer | Finding |
|-------|---------|
| Outer `.exe` | PE32 i386 GUI, 5 sections, clean PE ends at `0x1b1000` (~1.77 MB). Imports only `KERNEL32.dll` (`FindResourceW`, `CreateProcessW`, `GetTempPathW`, named pipes) → a **bootstrapper / installer stub** (build 2017-09-18, FileVersion 1.8.8). |
| Appended payload | ~433 MB after the stub: a **single compressed/packed blob** (not raw CAB/ZIP/MSI/7z — only 32 plain ZIP local headers exist in the whole file). Contains the real application. |
| Embedded ZIP @ ~74 MB | An **FTDI USB driver package** (`ftcserco.dll`, `ftlang.dll`, `x_lang.dll`, `*.sys`, `*.inf`) — a prerequisite, not the app. |
| CABs @ 435–446 MB | Small **Windows Update prerequisites** (e.g. `Windows6.0-KB2685811`). |
| Strings | German UI text confirmed present, stored as **UTF-16LE**. |

**Blocker:** the application's own German UI strings live inside the compressed
~433 MB payload. The partial set currently in `i18n/` is only the strings
visible *outside* that blob (FTDI/Windows installer boilerplate, some Danish/
Dutch). Two reliable ways to get the complete set:

1. **Install/run the app** (Windows or Wine), then run `scripts/extract_strings.py`
   against the installed `.exe`/`.dll` files. *(recommended — most reliable)*
2. Keep reverse-engineering the installer's custom compression to unpack the
   payload offline.

## Files

- `i18n/translations.de.json` — bilingual translation file (partial; schema below).
- `scripts/extract_strings.py` — extracts German UTF-16LE strings into that schema.

## Translation file schema

```json
{
  "meta": { "source": "...", "source_lang": "de", "target_lang": "", "note": "..." },
  "strings": [
    { "id": "s0001", "de": "Die Baudrate muss positiv sein.", "target": "", "context": "" }
  ]
}
```

A translating model fills each `target`; `de` stays as the reference key.

## Usage

```bash
# against an installed application binary (full set)
python3 -I scripts/extract_strings.py /path/to/BMWTOOL.exe -o i18n/translations.de.json --target-lang tr
```
