# 仓库自检：所有 .ps1 必须是 UTF-8 BOM，且能被 PowerShell 5.1 正常解析。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check.ps1 [-Smoke]
param([switch]$Smoke)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem -LiteralPath $Root -Recurse -Filter '*.ps1' |
    Where-Object { $_.FullName -notmatch '\\benchmarks\\results\\' })

$failed = 0
foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    if (-not $hasBom) {
        Write-Host ('FAIL BOM   ' + $f.FullName) -ForegroundColor Red
        $failed++
    }
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        Write-Host ('FAIL SYNTAX ' + $f.FullName) -ForegroundColor Red
        foreach ($e in $errors) { Write-Host ('  ' + $e.Message) }
        $failed++
    }
}

if ($Smoke) {
    $winCmd = Join-Path $PSScriptRoot 'win.cmd'
    & cmd /c ('"' + $winCmd + '" doctor')
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'FAIL SMOKE win doctor' -ForegroundColor Red
        $failed++
    }
}

if ($failed -eq 0) {
    Write-Output ('OK: {0} 个 .ps1 文件通过 BOM + 语法检查' -f $files.Count)
    exit 0
}
Write-Output ('FAIL: {0} 个问题' -f $failed)
exit 1
