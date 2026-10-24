# bimtool_translate

German → target-language translation project for **VVDI2 BMW TOOL** v1.8.8
(installer: `BMWTOOL-InstallerV188.exe`).

Goal: understand the application, extract its German UI strings, and produce a
**bilingual translation file** (`de` → `target`) that another model can fill in,
then merge back into the app.

> The proprietary installer and the installed app binaries are **not** committed
> (copyrighted). Only the extracted German source strings and tooling live here.

## What the app is

VVDI2 (Xhorse) BMW key-programming tool. Debug path in the binaries:
`E:\VVDI2\BMW2\Release\BMW_Language.pdb`.

## Reverse-engineering trail

Static RE with Ruflo's `rure_analyze_binary` (never executed the file):

| Layer | Finding |
|-------|---------|
| Outer `.exe` | PE32 stub, real PE ends ~1.77 MB; only imports `KERNEL32.dll` → an **Advanced Installer** bootstrapper (build 2017-09-18). |
| Packaging | **Advanced Installer + LZMA**. App files sit in an external LZMA payload (~428 MB) referenced by a product MSI; prerequisites are an FTDI USB-driver ZIP and Windows-Update CABs. |
| Product MSI | Languages: **English (base) + Chinese (2052)** — *no German here*. |
| App language resource | **`BMW_Language.dll`** — a serialized multilingual UI string table (German, English, Spanish, Italian, Polish, Hungarian, Danish, Chinese). **This is where the German UI text lives.** |

### How the strings were obtained

The silent/`msiexec` install route fails at Advanced Installer's proprietary
LZMA custom action under Wine. The **GUI wizard** (the real chainer) extracts
the LZMA payload correctly, installing the app to `C:\Program Files\BMW TOOL\`.
`BMW_Language.dll` was then parsed directly.

### String-table format

Flat sequence of **length-prefixed UTF-16LE** strings: `uint16` character count
(little-endian) + `count*2` bytes. Translations for all languages are
interleaved; German is selected by German-specific markers (`ä`, `ß`, German
function words) while excluding Hungarian/Polish/Spanish/Italian/Danish
(which share `ö`/`ü`).

## Files

- `i18n/translations.de.json` — **257** German UI strings **with English (`en`) and Turkish (`tr`) translations**, schema below.
- `i18n/translations.de.csv` — same, as `id,de,en,tr` (UTF-8 BOM, Excel-friendly).
- `scripts/extract_strings.py` — re-extracts German from `BMW_Language.dll`.

## Translation file schema

```json
{
  "meta": { "source": "BMW_Language.dll", "source_lang": "de", "target_lang": "en,tr", "count": 257 },
  "strings": [
    { "id": "s0001", "de": "Schlüssel via Dump", "en": "Key via Dump", "tr": "Dump ile anahtar", "context": "" }
  ]
}
```

`de` is the reference key; `en`/`tr` hold the translations. Placeholders
(`\n`, `\r\n`, `""..""`, `%s`/`%d`/`%.1X`, `<a>`) are preserved verbatim.

## Usage

```bash
python3 -I scripts/extract_strings.py "/path/to/BMW_Language.dll" \
    -o i18n/translations.de.json --csv i18n/translations.de.csv --target-lang tr
```
