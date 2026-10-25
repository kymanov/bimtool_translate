<#
.SYNOPSIS
    bmwtool_config.ini icinde verilen anahtarlari ekler/gunceller.
    Varsayilan: SKIPHTTP=1, SKIPACPRO=1 (Wine/online guncelleme cokmesini engeller).
    Windows PowerShell 5.1 uyumlu (ternary / ?? kullanilmaz).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Ini,
    [hashtable] $Settings = @{ 'SKIPHTTP' = '1'; 'SKIPACPRO' = '1' }
)
$ErrorActionPreference = "Stop"

if (Test-Path -LiteralPath $Ini) {
    $lines = [System.IO.File]::ReadAllLines($Ini)
} else {
    $lines = @()
}

$seen = @{}
$out = New-Object System.Collections.Generic.List[string]
foreach ($l in $lines) {
    $m = [regex]::Match($l, '^\s*([^=;#\s]+)\s*=')
    if ($m.Success) {
        $key = $m.Groups[1].Value.ToUpper()
        if ($Settings.ContainsKey($key)) {
            $out.Add($key + '=' + $Settings[$key])
            $seen[$key] = $true
            continue
        }
    }
    $out.Add($l)
}
foreach ($k in $Settings.Keys) {
    if (-not $seen.ContainsKey($k)) { $out.Add($k + '=' + $Settings[$k]) }
}

[System.IO.File]::WriteAllLines($Ini, $out.ToArray())
"config guncellendi: {0}" -f $Ini
