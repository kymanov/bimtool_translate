#!/usr/bin/env python3
"""Patch VVDI2 BMW_Language.dll: replace the German (Deutsch) RT_STRING slot
with a chosen translation (e.g. Turkish), producing a runnable DLL.

The UI text is stored as standard Win32 RT_STRING resources (16-string bundles).
This rebuilds every string bundle — replacing any string whose text matches a
German source with its translation (full length, no truncation) — then rewrites
the .rsrc section, patches every resource data-entry RVA/size, shifts .reloc, and
fixes the section headers. Section virtual addresses stay fixed, so relocations
remain valid. Select "Deutsch" in the app to see the translation; the built-in
"English" slot is untouched, so you can switch between them in the app.

Usage:
    python3 -I scripts/patch_language_dll.py BMW_Language.dll \
        i18n/translations.de.json --field tr -o BMW_Language.patched.dll
"""
import argparse
import json
import struct
import sys


def patch(dll_path, trans_path, field, out_path):
    d = bytearray(open(dll_path, "rb").read())
    data = json.load(open(trans_path, encoding="utf-8"))["strings"]
    tr = {x["de"]: x[field] for x in data if x.get(field)}

    pe = struct.unpack_from("<I", d, 0x3C)[0]
    nsec = struct.unpack_from("<H", d, pe + 6)[0]
    opt = struct.unpack_from("<H", d, pe + 20)[0]
    magic = struct.unpack_from("<H", d, pe + 24)[0]
    falign = struct.unpack_from("<I", d, pe + 24 + 36)[0]
    so = pe + 24 + opt
    secs = {}
    for i in range(nsec):
        o = so + i * 40
        name = d[o:o + 8].rstrip(b"\0").decode("latin1")
        vs, va, rs, ro = struct.unpack_from("<IIII", d, o + 8)
        secs[name] = [o, vs, va, rs, ro]
    va0, ro0 = secs[".rsrc"][2], secs[".rsrc"][4]
    next_va = secs[".reloc"][2]

    def r2f(r):
        return r - va0 + ro0

    ents = []

    def walk(off, path):
        nnamed, nid = struct.unpack_from("<HH", d, ro0 + off + 12)
        base = ro0 + off + 16
        for k in range(nnamed + nid):
            nameid, o = struct.unpack_from("<II", d, base + k * 8)
            if o & 0x80000000:
                walk(o & 0x7FFFFFFF, path + [nameid & 0x7FFFFFFF])
            else:
                de = ro0 + o
                drva, size, _, _ = struct.unpack_from("<IIII", d, de)
                ents.append([de, drva, size, path + [nameid]])

    walk(0, [])
    data_start_rva = min(e[1] for e in ents)
    prefix = bytearray(d[ro0:r2f(data_start_rva)])
    assert all(e[1] >= data_start_rva for e in ents), "data precedes directory"

    def rebuild_bundle(blob):
        out = bytearray()
        i = 0
        for _ in range(16):
            if i + 2 > len(blob):
                out += blob[i:]
                break
            ln = blob[i] | (blob[i + 1] << 8)
            i += 2
            s = bytes(blob[i:i + ln * 2])
            i += ln * 2
            try:
                txt = s.decode("utf-16-le")
            except Exception:
                txt = None
            if txt is not None and txt in tr:
                out += struct.pack("<H", len(tr[txt])) + tr[txt].encode("utf-16-le")
            else:
                out += struct.pack("<H", ln) + s
        return bytes(out)

    new_data = bytearray()
    for de, drva, size, path in sorted(ents, key=lambda e: e[1]):
        blob = bytes(d[r2f(drva):r2f(drva) + size])
        nb = rebuild_bundle(blob) if path[0] == 6 else blob
        while len(new_data) % 4:
            new_data.append(0)
        new_rva = data_start_rva + len(new_data)
        struct.pack_into("<II", prefix, de - ro0, new_rva, len(nb))
        new_data += nb

    new_rsrc = bytes(prefix) + bytes(new_data)
    new_vs = len(new_rsrc)
    assert va0 + new_vs <= next_va, "rsrc virtual overflow — would need section shift"
    new_raw = (len(new_rsrc) + falign - 1) // falign * falign
    new_rsrc_padded = new_rsrc + b"\0" * (new_raw - len(new_rsrc))

    reloc_raw = bytes(d[secs[".reloc"][4]:secs[".reloc"][4] + secs[".reloc"][3]])
    head = bytearray(d[:ro0])
    struct.pack_into("<I", head, secs[".rsrc"][0] + 8, new_vs)          # VirtualSize
    struct.pack_into("<I", head, secs[".rsrc"][0] + 16, new_raw)        # SizeOfRawData
    struct.pack_into("<I", head, secs[".reloc"][0] + 20, ro0 + new_raw) # .reloc PointerToRawData
    ddoff = pe + 24 + (96 if magic == 0x10B else 112)
    struct.pack_into("<I", head, ddoff + 2 * 8 + 4, new_vs)             # resource dir size
    struct.pack_into("<I", head, pe + 24 + 64, 0)                       # zero checksum

    open(out_path, "wb").write(bytes(head) + new_rsrc_padded + reloc_raw)
    print(f"patched {out_path}: {len(tr)} source strings, new .rsrc vsize={new_vs:#x}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dll", help="BMW_Language.dll (original)")
    ap.add_argument("translations", help="translations JSON (de + target fields)")
    ap.add_argument("--field", default="tr", help="target field to apply: tr | en")
    ap.add_argument("-o", "--out", default="BMW_Language.patched.dll")
    a = ap.parse_args()
    patch(a.dll, a.translations, a.field, a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
