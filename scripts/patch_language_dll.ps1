<#
.SYNOPSIS
    VVDI2 BMW_Language.dll patcher -- NO Python required (pure PowerShell).

.DESCRIPTION
    A faithful PowerShell port of scripts/patch_language_dll.py.
    Replaces the German (Deutsch) RT_STRING resource slot with a chosen
    translation (e.g. Turkish) and produces a runnable DLL. The UI text is
    stored as standard Win32 RT_STRING resources (bundles of 16 strings). This
    script rebuilds every string bundle -- replacing any string whose source
    text matches a German entry with its translation (full length, no
    truncation) -- then rewrites the .rsrc section, patches every resource
    data-entry RVA/size, shifts .reloc, and fixes the section headers. Section
    virtual addresses stay fixed, so relocations remain valid. Pick "Deutsch"
    in the app to see the translation; the built-in "English" slot is untouched.

    ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less .ps1 files as
    the system ANSI codepage, so non-ASCII bytes would break parsing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\patch_language_dll.ps1 `
        -Dll BMW_Language.dll -Translations i18n\translations.de.json `
        -Field tr -Out BMW_Language.patched.dll
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Dll,            # BMW_Language.dll (original)
    [Parameter(Mandatory = $true)] [string] $Translations,   # translations JSON (de + target fields)
    [string] $Field = "tr",                                  # target field to apply: tr | en
    [string] $Out   = "BMW_Language.patched.dll"
)

$ErrorActionPreference = "Stop"

function Read-U16([byte[]]$b, [int]$off) { return [BitConverter]::ToUInt16($b, $off) }
function Read-U32([byte[]]$b, [int]$off) { return [BitConverter]::ToUInt32($b, $off) }
function Set-U32([byte[]]$b, [int]$off, [uint32]$val) {
    $bytes = [BitConverter]::GetBytes([uint32]$val)
    [Array]::Copy($bytes, 0, $b, $off, 4)
}

$Dll          = (Resolve-Path -LiteralPath $Dll).Path
$Translations = (Resolve-Path -LiteralPath $Translations).Path

$d = [System.IO.File]::ReadAllBytes($Dll)

# ---- load translations: de -> target (case-sensitive, ordinal) ----
$jsonText = [System.IO.File]::ReadAllText($Translations, [System.Text.Encoding]::UTF8)
$strings  = (ConvertFrom-Json $jsonText).strings
$tr = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($x in $strings) {
    $val = $x.$Field
    if (-not [string]::IsNullOrEmpty($val)) { $tr[$x.de] = $val }
}

# ---- read PE headers ----
$pe     = Read-U32 $d 0x3C
$nsec   = Read-U16 $d ($pe + 6)
$opt    = Read-U16 $d ($pe + 20)
$magic  = Read-U16 $d ($pe + 24)
$falign = Read-U32 $d ($pe + 24 + 36)
$so     = $pe + 24 + $opt

$secs = @{}
for ($i = 0; $i -lt $nsec; $i++) {
    $o    = $so + $i * 40
    $name = ([System.Text.Encoding]::ASCII.GetString($d, $o, 8)).TrimEnd([char]0)
    $vs   = Read-U32 $d ($o + 8)
    $va   = Read-U32 $d ($o + 12)
    $rs   = Read-U32 $d ($o + 16)
    $ro   = Read-U32 $d ($o + 20)
    $secs[$name] = @($o, $vs, $va, $rs, $ro)   # [headerOff, VirtualSize, VirtualAddr, RawSize, RawPtr]
}
$va0     = [int]$secs[".rsrc"][2]
$ro0     = [int]$secs[".rsrc"][4]
$next_va = [int]$secs[".reloc"][2]

function R2F([int]$r) { return $r - $va0 + $ro0 }

# ---- walk the resource tree, collect every data entry ----
$script:ents = New-Object System.Collections.ArrayList

function Walk([int]$off, [int[]]$path) {
    $nnamed = Read-U16 $d ($ro0 + $off + 12)
    $nid    = Read-U16 $d ($ro0 + $off + 14)
    $base   = $ro0 + $off + 16
    for ($k = 0; $k -lt ($nnamed + $nid); $k++) {
        $nameid = Read-U32 $d ($base + $k * 8)
        $o      = Read-U32 $d ($base + $k * 8 + 4)
        if ($o -band 0x80000000) {
            Walk ($o -band 0x7FFFFFFF) ($path + ([int]($nameid -band 0x7FFFFFFF)))
        } else {
            $de   = $ro0 + $o
            $drva = Read-U32 $d $de
            $size = Read-U32 $d ($de + 4)
            [void]$script:ents.Add(@([int]$de, [int]$drva, [int]$size, ($path + [int]$nameid)))
        }
    }
}
Walk 0 @()

$data_start_rva = ($script:ents | ForEach-Object { $_[1] } | Measure-Object -Minimum).Minimum
foreach ($e in $script:ents) {
    if ($e[1] -lt $data_start_rva) { throw "data precedes directory" }
}

# prefix = resource directory block (everything before the first data entry)
$prefixLen = (R2F $data_start_rva) - $ro0
$prefix = New-Object byte[] $prefixLen
[Array]::Copy($d, $ro0, $prefix, 0, $prefixLen)

$uni = [System.Text.Encoding]::Unicode   # UTF-16LE

function Rebuild-Bundle([byte[]]$blob) {
    $out = New-Object System.Collections.Generic.List[byte]
    $i = 0
    for ($n = 0; $n -lt 16; $n++) {
        if ($i + 2 -gt $blob.Length) {
            for ($j = $i; $j -lt $blob.Length; $j++) { $out.Add($blob[$j]) }
            break
        }
        # [int] cast is required: with a [byte] left operand, -shl truncates to a
        # byte ([byte]1 -shl 8 = 0), which would corrupt the length prefix.
        $ln = [int]$blob[$i] -bor ([int]$blob[$i + 1] -shl 8)
        $i += 2
        $sLen = $ln * 2
        # Match Python slicing: clip a length that runs past the blob end, but
        # still advance i by the full declared length (preserve malformed tails).
        $avail = $blob.Length - $i
        if ($avail -lt 0) { $avail = 0 }
        $copyLen = [Math]::Min($sLen, $avail)
        $s = New-Object byte[] $copyLen
        if ($copyLen -gt 0) { [Array]::Copy($blob, $i, $s, 0, $copyLen) }
        $i += $sLen
        $txt = $uni.GetString($s)
        if ($tr.ContainsKey($txt)) {
            $tb = $uni.GetBytes($tr[$txt])
            $out.Add([byte]((($tb.Length / 2)) -band 0xFF))
            $out.Add([byte]((($tb.Length / 2) -shr 8) -band 0xFF))
            if ($tb.Length -gt 0) { $out.AddRange($tb) }
        } else {
            $out.Add([byte]($ln -band 0xFF))
            $out.Add([byte](($ln -shr 8) -band 0xFF))
            if ($s.Length -gt 0) { $out.AddRange($s) }
        }
    }
    return ,$out.ToArray()   # unary comma: stops PowerShell from unrolling the array
}

# ---- rebuild data blocks in RVA order ----
$new_data = New-Object System.Collections.Generic.List[byte]
$sorted = $script:ents | Sort-Object { $_[1] }
foreach ($e in $sorted) {
    $de = [int]$e[0]; $drva = [int]$e[1]; $size = [int]$e[2]; $path = $e[3]
    $f = R2F $drva
    $blob = New-Object byte[] $size
    if ($size -gt 0) { [Array]::Copy($d, $f, $blob, 0, $size) }
    if ($path[0] -eq 6) { $nb = [byte[]](Rebuild-Bundle $blob) } else { $nb = [byte[]]$blob }
    while ($new_data.Count % 4 -ne 0) { $new_data.Add([byte]0) }
    $new_rva = $data_start_rva + $new_data.Count
    Set-U32 $prefix ($de - $ro0) ([uint32]$new_rva)
    Set-U32 $prefix ($de - $ro0 + 4) ([uint32]$nb.Length)
    if ($nb.Length -gt 0) { $new_data.AddRange($nb) }
}

# ---- assemble the new .rsrc ----
$new_rsrc = New-Object System.Collections.Generic.List[byte]
$new_rsrc.AddRange($prefix)
$new_rsrc.AddRange($new_data.ToArray())
$new_vs = $new_rsrc.Count
if (($va0 + $new_vs) -gt $next_va) { throw "rsrc virtual overflow -- would need a section shift" }
$new_raw = [int]([math]::Floor(($new_vs + $falign - 1) / $falign) * $falign)
$new_rsrc_padded = New-Object byte[] $new_raw
[Array]::Copy($new_rsrc.ToArray(), 0, $new_rsrc_padded, 0, $new_vs)
# (remaining bytes are already 0)

# ---- .reloc raw data ----
$reloc_ro = [int]$secs[".reloc"][4]
$reloc_rs = [int]$secs[".reloc"][3]
$reloc_raw = New-Object byte[] $reloc_rs
if ($reloc_rs -gt 0) { [Array]::Copy($d, $reloc_ro, $reloc_raw, 0, $reloc_rs) }

# ---- copy the header and patch it ----
$head = New-Object byte[] $ro0
[Array]::Copy($d, 0, $head, 0, $ro0)
Set-U32 $head ([int]$secs[".rsrc"][0] + 8)  ([uint32]$new_vs)           # .rsrc VirtualSize
Set-U32 $head ([int]$secs[".rsrc"][0] + 16) ([uint32]$new_raw)         # .rsrc SizeOfRawData
Set-U32 $head ([int]$secs[".reloc"][0] + 20) ([uint32]($ro0 + $new_raw)) # .reloc PointerToRawData
if ($magic -eq 0x10B) { $ddoff = $pe + 24 + 96 } else { $ddoff = $pe + 24 + 112 }
Set-U32 $head ($ddoff + 2 * 8 + 4) ([uint32]$new_vs)                  # resource directory size
Set-U32 $head ($pe + 24 + 64) ([uint32]0)                             # zero the checksum

# ---- write the output ----
$fs = [System.IO.File]::Open($Out, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
try {
    $fs.Write($head, 0, $head.Length)
    $fs.Write($new_rsrc_padded, 0, $new_rsrc_padded.Length)
    $fs.Write($reloc_raw, 0, $reloc_raw.Length)
} finally {
    $fs.Dispose()
}

"patched {0}: {1} source strings, new .rsrc vsize=0x{2:X}" -f $Out, $tr.Count, $new_vs
