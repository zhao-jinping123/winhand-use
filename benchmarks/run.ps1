# winhand-use 公开基准：把「能控到什么层、是否打扰用户、动作是否被验证」量化成可重跑的 JSON。
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File benchmarks\run.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File benchmarks\run.ps1 -SkipRealApps -SkipProbe
[CmdletBinding()]
param(
    [string]$OutDir = '',
    [switch]$SkipRealApps,
    [switch]$SkipProbe,
    [switch]$ProbeOnly
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Win = Join-Path $RepoRoot 'scripts\win.ps1'
$Probe = Join-Path $RepoRoot 'scripts\probe.ps1'
$Targets = Join-Path $PSScriptRoot 'targets'
$BuildTargets = Join-Path $Targets 'build-targets.ps1'

if (-not $OutDir) {
    $OutDir = Join-Path $PSScriptRoot ('results\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$Shots = Join-Path $OutDir 'shots'
New-Item -ItemType Directory -Path $Shots -Force | Out-Null

$script:Results = New-Object System.Collections.ArrayList
$script:ProbeRows = New-Object System.Collections.ArrayList
$script:FailCount = 0
$script:SkipCount = 0
$script:PassCount = 0
$script:RunStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Invoke-Win {
    param([string[]]$WinArgs)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Win @WinArgs 2>&1
    $code = $LASTEXITCODE
    [pscustomobject]@{
        Code = $code
        Text = (($out | ForEach-Object { $_.ToString() }) -join "`n")
    }
}

function Invoke-Probe {
    param([string]$App)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Probe $App 2>&1
    $code = $LASTEXITCODE
    [pscustomobject]@{
        Code = $code
        Text = (($out | ForEach-Object { $_.ToString() }) -join "`n")
    }
}

function Find-Window {
    param([string]$Keyword)
    $r = Invoke-Win @('windows', $Keyword)
    $line = ($r.Text -split "`r?`n" | Where-Object { $_ -match 'hwnd=0x' } | Select-Object -First 1)
    if (-not $line) { return $null }
    $h = [regex]::Match($line, 'hwnd=(0x[0-9A-Fa-f]+)')
    $rect = [regex]::Match($line, 'rect=\((-?\d+),(-?\d+),(\d+),(\d+)\)')
    [pscustomobject]@{
        Hwnd = $(if ($h.Success) { $h.Groups[1].Value } else { '' })
        Line = $line
        Left = $(if ($rect.Success) { [int]$rect.Groups[1].Value } else { 0 })
        Top = $(if ($rect.Success) { [int]$rect.Groups[2].Value } else { 0 })
        Width = $(if ($rect.Success) { [int]$rect.Groups[3].Value } else { 0 })
        Height = $(if ($rect.Success) { [int]$rect.Groups[4].Value } else { 0 })
    }
}

function Get-ForegroundHwnd {
    $r = Invoke-Win @('fg')
    $m = [regex]::Match($r.Text, 'hwnd=(0x[0-9A-Fa-f]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Get-ShotInfo {
    param([string]$Text)
    $black = [regex]::Match($Text, 'black=([0-9.]+)')
    $path = [regex]::Match($Text, 'path=([^\r\n]+\.png)')
    $size = [regex]::Match($Text, 'size=(\d+x\d+)')
    [pscustomobject]@{
        Black = $(if ($black.Success) { [double]$black.Groups[1].Value } else { -1 })
        Path = $(if ($path.Success) { $path.Groups[1].Value.Trim() } else { '' })
        Size = $(if ($size.Success) { $size.Groups[1].Value } else { '' })
    }
}

function Select-Element {
    param([string]$Text, [string]$Keyword)
    $lines = @($Text -split "`r?`n")
    $line = @($lines | Where-Object { $_ -match '^(e\d+)\s' -and $_ -match [regex]::Escape($Keyword) } | Select-Object -First 1)
    if (-not $line) {
        $line = @($lines | Where-Object { $_ -match '^(e\d+)\s' } | Select-Object -First 1)
    }
    if ($line.Count -eq 0) { return '' }
    $m = [regex]::Match($line[0], '^(e\d+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Add-Result {
    param(
        [string]$Id,
        [string]$Layer,
        [string]$Status,
        [string]$Detail,
        [int]$DurationMs,
        [string[]]$Evidence = @()
    )
    $script:Results.Add([pscustomobject]@{
        id = $Id
        layer = $Layer
        status = $Status
        detail = $Detail
        duration_ms = $DurationMs
        evidence = @($Evidence)
    }) | Out-Null
    switch ($Status) {
        'pass' { $script:PassCount++ }
        'skip' { $script:SkipCount++ }
        default { $script:FailCount++ }
    }
    Write-Host ('[{0}] {1} ({2} ms) {3}' -f $Status.ToUpper(), $Id, $DurationMs, $Detail)
}

function Invoke-Scenario {
    param([string]$Id, [string]$Layer, [scriptblock]$Body)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = & $Body
        if ($r -and $r.Status) {
            $sw.Stop()
            Add-Result -Id $Id -Layer $Layer -Status $r.Status -Detail $r.Detail -DurationMs $sw.ElapsedMilliseconds -Evidence @($r.Evidence)
            return
        }
        $sw.Stop()
        Add-Result -Id $Id -Layer $Layer -Status 'fail' -Detail '场景没有返回结果对象' -DurationMs $sw.ElapsedMilliseconds
    }
    catch {
        $sw.Stop()
        Add-Result -Id $Id -Layer $Layer -Status 'fail' -Detail $_.Exception.Message -DurationMs $sw.ElapsedMilliseconds
    }
}

function Start-Sandbox {
    param([string]$Tag)
    $exe = Join-Path $Targets 'sandbox-form.exe'
    if (-not (Test-Path $exe)) { throw 'sandbox-form.exe 不存在，请先运行 benchmarks\targets\build-targets.ps1' }
    $effect = Join-Path $OutDir ('sandbox-' + $Tag + '.effect.txt')
    $marker = Join-Path $OutDir ('sandbox-' + $Tag + '.marker.txt')
    Remove-Item -LiteralPath $effect, $marker -Force -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $exe -ArgumentList @($effect, $marker) -WindowStyle Minimized -PassThru
    $info = $null
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 300
        $info = Find-Window 'winhand-bench-sandbox'
        if ($info -and $info.Hwnd) { break }
    }
    if (-not $info -or -not $info.Hwnd) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        throw '沙箱窗口 9 秒内没有出现'
    }
    # 用 show 无激活还原，保证用户当前前台窗口不被测试靶标抢走。
    Invoke-Win @('show', $info.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 400
    $info = Find-Window 'winhand-bench-sandbox'
    [pscustomobject]@{
        Proc = $p
        Hwnd = $info.Hwnd
        Info = $info
        Effect = $effect
        Marker = $marker
    }
}

function Stop-Sandbox {
    param($Context)
    if ($Context -and $Context.Proc) {
        Stop-Process -Id $Context.Proc.Id -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '编译基准靶标...'
& powershell -NoProfile -ExecutionPolicy Bypass -File $BuildTargets | Out-Null

# ───────────────────────── 沙箱能力项 ─────────────────────────

if (-not $ProbeOnly) {

Invoke-Scenario -Id 'sandbox.see' -Layer 'L1' -Body {
    $ctx = Start-Sandbox -Tag 'see'
    try {
        $fgBefore = Get-ForegroundHwnd
        $r = Invoke-Win @('see', $ctx.Hwnd, '--out', $Shots)
        $shot = Get-ShotInfo $r.Text
        $editable = [regex]::Match($r.Text, 'editable=(\d+)')
        $shotOk = $shot.Path -and (Test-Path -LiteralPath $shot.Path) -and $shot.Black -ge 0 -and $shot.Black -lt 0.99
        $uiOk = $editable.Success -and [int]$editable.Groups[1].Value -ge 2 -and $r.Text -match 'inputA' -and $r.Text -match 'inputB'
        $fgAfter = Get-ForegroundHwnd
        $status = $(if ($shotOk -and $uiOk) { 'pass' } else { 'fail' })
        [pscustomobject]@{
            Status = $status
            Detail = ('截图={0} black={1} editable={2} UIA含双输入框={3} 前台未变={4}' -f $shotOk, $shot.Black, $(if ($editable.Success) { $editable.Groups[1].Value } else { '?' }), $uiOk, ($fgBefore -eq $fgAfter))
            Evidence = @($shot.Path)
        }
    }
    finally { Stop-Sandbox $ctx }
}

Invoke-Scenario -Id 'sandbox.axset' -Layer 'L1' -Body {
    $ctx = Start-Sandbox -Tag 'axset'
    try {
        $ax = Invoke-Win @('ax', $ctx.Hwnd, 'inputB')
        $sel = Select-Element $ax.Text 'inputB'
        $text = '基准写入-20260912'
        $fgBefore = Get-ForegroundHwnd
        $write = Invoke-Win @('axset', $ctx.Hwnd, $sel, $text)
        Start-Sleep -Milliseconds 300
        $read = Invoke-Win @('ax', $ctx.Hwnd, 'inputB')
        $fgAfter = Get-ForegroundHwnd
        $ok = $sel -and $read.Text -match [regex]::Escape($text) -and $write.Text -match 'effect=confirmed'
        [pscustomobject]@{
            Status = $(if ($ok) { 'pass' } else { 'fail' })
            Detail = ('selector={0} 写回一致={1} effect=confirmed={2} 前台未变={3}' -f $sel, ($read.Text -match [regex]::Escape($text)), ($write.Text -match 'effect=confirmed'), ($fgBefore -eq $fgAfter))
            Evidence = @()
        }
    }
    finally { Stop-Sandbox $ctx }
}

Invoke-Scenario -Id 'sandbox.axpress' -Layer 'L1' -Body {
    $ctx = Start-Sandbox -Tag 'axpress'
    try {
        $axA = Invoke-Win @('ax', $ctx.Hwnd, 'inputA')
        $selA = Select-Element $axA.Text 'inputA'
        $axBtn = Invoke-Win @('ax', $ctx.Hwnd, '提交')
        $selBtn = Select-Element $axBtn.Text '提交'
        $textA = '按钮落盘-20260912'
        Invoke-Win @('axset', $ctx.Hwnd, $selA, $textA) | Out-Null
        $fgBefore = Get-ForegroundHwnd
        $press = Invoke-Win @('axpress', $ctx.Hwnd, $selBtn)
        Start-Sleep -Milliseconds 600
        $effectText = $(if (Test-Path -LiteralPath $ctx.Effect) { [System.IO.File]::ReadAllText($ctx.Effect, [System.Text.Encoding]::UTF8) } else { '' })
        $fgAfter = Get-ForegroundHwnd
        $ok = $selBtn -and $effectText -match 'state=saved' -and $effectText -match [regex]::Escape($textA) -and ($fgBefore -eq $fgAfter)
        [pscustomobject]@{
            Status = $(if ($ok) { 'pass' } else { 'fail' })
            Detail = ('button={0} 副作用落盘={1} 内容一致={2} 前台未变={3}' -f $selBtn, ($effectText -match 'state=saved'), ($effectText -match [regex]::Escape($textA)), ($fgBefore -eq $fgAfter))
            Evidence = @($ctx.Effect)
        }
    }
    finally { Stop-Sandbox $ctx }
}

Invoke-Scenario -Id 'sandbox.occluded_shot' -Layer 'L3' -Body {
    $ctx = Start-Sandbox -Tag 'occluded'
    $cover = $null
    try {
        $coverExe = Join-Path $Targets 'cover-window.exe'
        $cover = Start-Process -FilePath $coverExe -ArgumentList @($ctx.Info.Left, $ctx.Info.Top, $ctx.Info.Width, $ctx.Info.Height) -WindowStyle Minimized -PassThru
        $coverInfo = $null
        for ($i = 0; $i -lt 15; $i++) {
            Start-Sleep -Milliseconds 300
            $coverInfo = Find-Window 'winhand-bench-cover'
            if ($coverInfo -and $coverInfo.Hwnd) { break }
        }
        if ($coverInfo -and $coverInfo.Hwnd) {
            Invoke-Win @('show', $coverInfo.Hwnd, '--above', $ctx.Hwnd) | Out-Null
        }
        Start-Sleep -Milliseconds 600
        $fgBefore = Get-ForegroundHwnd
        $png = Join-Path $Shots 'occluded-sandbox.png'
        $r = Invoke-Win @('shot', $ctx.Hwnd, $png)
        $shot = Get-ShotInfo $r.Text
        $fgAfter = Get-ForegroundHwnd
        $ok = (Test-Path -LiteralPath $png) -and $shot.Black -ge 0 -and $shot.Black -lt 0.99
        [pscustomobject]@{
            Status = $(if ($ok) { 'pass' } else { 'fail' })
            Detail = ('遮挡下截图={0} black={1} 截图前后前台未变={2}' -f (Test-Path -LiteralPath $png), $shot.Black, ($fgBefore -eq $fgAfter))
            Evidence = @($png)
        }
    }
    finally {
        if ($cover) { Stop-Process -Id $cover.Id -Force -ErrorAction SilentlyContinue }
        Stop-Sandbox $ctx
    }
}

Invoke-Scenario -Id 'sandbox.op_dry' -Layer 'L2' -Body {
    $ctx = Start-Sandbox -Tag 'opdry'
    try {
        $fgBefore = Get-ForegroundHwnd
        $r = Invoke-Win @('op', $ctx.Hwnd, '120', '200', 'dry-run', '--dry')
        $fgAfter = Get-ForegroundHwnd
        $dryOk = $r.Text -match 'dry|预演|闸'
        $noEffect = -not (Test-Path -LiteralPath $ctx.Effect)
        [pscustomobject]@{
            Status = $(if ($dryOk -and $noEffect -and ($fgBefore -eq $fgAfter)) { 'pass' } else { 'fail' })
            Detail = ('dry预演可见={0} 未执行副作用={1} 前台未变={2} exit={3}' -f $dryOk, $noEffect, ($fgBefore -eq $fgAfter), $r.Code)
            Evidence = @()
        }
    }
    finally { Stop-Sandbox $ctx }
}

}

# ───────────────────────── 真实应用（只读/自建实例） ─────────────────────────

if ((-not $SkipRealApps) -and (-not $ProbeOnly)) {
    Invoke-Scenario -Id 'real.explorer_desktop' -Layer 'L1/L3' -Body {
        $r = Invoke-Win @('windows')
        $line = ($r.Text -split "`r?`n" | Where-Object { $_ -match 'owner=explorer' -and $_ -match 'title=Program Manager' } | Select-Object -First 1)
        if (-not $line) {
            return [pscustomobject]@{ Status = 'skip'; Detail = '当前系统没有找到 Program Manager 桌面窗口'; Evidence = @() }
        }
        $hwnd = [regex]::Match($line, 'hwnd=(0x[0-9A-Fa-f]+)').Groups[1].Value
        $png = Join-Path $Shots 'explorer-desktop.png'
        $shot = Invoke-Win @('shot', $hwnd, $png)
        $info = Get-ShotInfo $shot.Text
        $ax = Invoke-Win @('ax', $hwnd)
        $ok = (Test-Path -LiteralPath $png) -and $info.Black -lt 0.99 -and $ax.Text -match 'uia=on'
        [pscustomobject]@{
            Status = $(if ($ok) { 'pass' } else { 'fail' })
            Detail = ('桌面截图={0} black={1} UIA可读={2}' -f (Test-Path -LiteralPath $png), $info.Black, ($ax.Text -match 'uia=on'))
            Evidence = @($png)
        }
    }

    Invoke-Scenario -Id 'real.notepad' -Layer 'L0/L1' -Body {
        $preexisting = @(Get-Process notepad -ErrorAction SilentlyContinue)
        if ($preexisting.Count -gt 0) {
            return [pscustomobject]@{ Status = 'skip'; Detail = '用户已有记事本进程，跳过以避免干扰'; Evidence = @() }
        }
        $doc = Join-Path $OutDir 'bench-notepad.txt'
        [System.IO.File]::WriteAllText($doc, 'winhand benchmark notepad 20260912', (New-Object System.Text.UTF8Encoding($false)))
        $p = Start-Process -FilePath 'notepad.exe' -ArgumentList @($doc) -WindowStyle Minimized -PassThru
        $info = $null
        for ($i = 0; $i -lt 25; $i++) {
            Start-Sleep -Milliseconds 300
            $info = Find-Window 'bench-notepad'
            if ($info -and $info.Hwnd) { break }
        }
        if (-not $info -or -not $info.Hwnd) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            return [pscustomobject]@{ Status = 'skip'; Detail = '记事本窗口未在 7.5 秒内出现'; Evidence = @() }
        }
        Invoke-Win @('show', $info.Hwnd) | Out-Null
        Start-Sleep -Milliseconds 400
        $info = Find-Window 'bench-notepad'
        $png = Join-Path $Shots 'notepad.png'
        $shot = Invoke-Win @('shot', $info.Hwnd, $png)
        $sinfo = Get-ShotInfo $shot.Text
        $ax = Invoke-Win @('ax', $info.Hwnd)
        $ok = (Test-Path -LiteralPath $png) -and $sinfo.Black -lt 0.99
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Status = $(if ($ok) { 'pass' } else { 'fail' })
            Detail = ('后台截图={0} black={1} UIA元素={2}' -f (Test-Path -LiteralPath $png), $sinfo.Black, ([regex]::Match($ax.Text, 'elements=(\d+)').Groups[1].Value))
            Evidence = @($png)
        }
    }

    Invoke-Scenario -Id 'real.calculator' -Layer 'L1/L3' -Body {
        $preexisting = @(Get-Process CalculatorApp, Calculator, calc -ErrorAction SilentlyContinue)
        if ($preexisting.Count -gt 0) {
            return [pscustomobject]@{ Status = 'skip'; Detail = '用户已有计算器进程，跳过以避免干扰'; Evidence = @() }
        }
        $p = Start-Process -FilePath 'calc.exe' -WindowStyle Minimized -PassThru
        $info = $null
        for ($i = 0; $i -lt 25; $i++) {
            Start-Sleep -Milliseconds 300
            $info = Find-Window '计算器'
            if (-not $info) { $info = Find-Window 'Calculator' }
            if ($info -and $info.Hwnd) { break }
        }
        if (-not $info -or -not $info.Hwnd) {
            Get-Process CalculatorApp, Calculator, calc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            return [pscustomobject]@{ Status = 'skip'; Detail = '计算器窗口未在 7.5 秒内出现'; Evidence = @() }
        }
        Invoke-Win @('show', $info.Hwnd) | Out-Null
        Start-Sleep -Milliseconds 400
        $info = Find-Window '计算器'
        if (-not $info) { $info = Find-Window 'Calculator' }
        $png = Join-Path $Shots 'calculator.png'
        $shot = Invoke-Win @('shot', $info.Hwnd, $png)
        $sinfo = Get-ShotInfo $shot.Text
        $ax = Invoke-Win @('ax', $info.Hwnd)
        $ok = (Test-Path -LiteralPath $png) -and $sinfo.Black -lt 0.99
        Get-Process CalculatorApp, Calculator, calc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Status = $(if ($ok) { 'pass' } else { 'fail' })
            Detail = ('后台截图={0} black={1} UIA元素={2}' -f (Test-Path -LiteralPath $png), $sinfo.Black, ([regex]::Match($ax.Text, 'elements=(\d+)').Groups[1].Value))
            Evidence = @($png)
        }
    }

    Invoke-Scenario -Id 'real.mspaint' -Layer 'L1/L3' -Body {
        $preexisting = @(Get-Process mspaint -ErrorAction SilentlyContinue)
        if ($preexisting.Count -gt 0) {
            return [pscustomobject]@{ Status = 'skip'; Detail = '用户已有画图进程，跳过以避免干扰'; Evidence = @() }
        }
        $p = Start-Process -FilePath 'mspaint.exe' -WindowStyle Minimized -PassThru
        $info = $null
        for ($i = 0; $i -lt 25; $i++) {
            Start-Sleep -Milliseconds 300
            $info = Find-Window '画图'
            if (-not $info) { $info = Find-Window 'Paint' }
            if ($info -and $info.Hwnd) { break }
        }
        if (-not $info -or -not $info.Hwnd) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            return [pscustomobject]@{ Status = 'skip'; Detail = '画图窗口未在 7.5 秒内出现'; Evidence = @() }
        }
        Invoke-Win @('show', $info.Hwnd) | Out-Null
        Start-Sleep -Milliseconds 400
        $info = Find-Window '画图'
        if (-not $info) { $info = Find-Window 'Paint' }
        $png = Join-Path $Shots 'mspaint.png'
        $shot = Invoke-Win @('shot', $info.Hwnd, $png)
        $sinfo = Get-ShotInfo $shot.Text
        $ax = Invoke-Win @('ax', $info.Hwnd)
        $ok = (Test-Path -LiteralPath $png) -and $sinfo.Black -lt 0.99
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Status = $(if ($ok) { 'pass' } else { 'fail' })
            Detail = ('后台截图={0} black={1} UIA元素={2}' -f (Test-Path -LiteralPath $png), $sinfo.Black, ([regex]::Match($ax.Text, 'elements=(\d+)').Groups[1].Value))
            Evidence = @($png)
        }
    }
}

# ───────────────────────── 常用软件探测矩阵 ─────────────────────────

if (-not $SkipProbe) {
    $apps = @('notepad', 'calc', 'mspaint', 'explorer', 'msedge', 'chrome', 'Code', 'Weixin', 'DingTalk', 'wps', 'JianyingPro', 'Doubao')
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $found = 0
    $probeErrors = 0
    foreach ($app in $apps) {
        $r = Invoke-Probe $app
        $hasError = $r.Text -match 'Unexpected token|ParserError|CategoryInfo'
        $isFound = (-not $hasError) -and (-not ($r.Text -match '找不到应用'))
        if ($hasError) { $probeErrors++ }
        if ($isFound) { $found++ }
        $version = [regex]::Match($r.Text, '版本:\s*([^\r\n#]+)').Groups[1].Value.Trim()
        $path = [regex]::Match($r.Text, '路径:\s*([^\r\n]+)').Groups[1].Value.Trim()
        $chromium = $r.Text -match 'Chromium系\(Electron/CEF\): 是'
        $cdp = $r.Text -match 'CDP ✅'
        $note = $(if ($hasError) { '探针解析错误' } elseif ($isFound) { '' } else { '未找到应用' })
        $script:ProbeRows.Add([pscustomobject]@{
            app = $app
            found = $isFound
            path = $path
            version = $version
            chromium = $chromium
            cdp = $cdp
            note = $note
            exit_code = $r.Code
            raw = $r.Text
        }) | Out-Null
    }
    $sw.Stop()
    $script:ProbeRows | ForEach-Object { $_.PSObject.Properties.Remove('raw') } | Out-Null
    Add-Result -Id 'probe.matrix' -Layer 'L0/L1' -Status $(if ($probeErrors -gt 0) { 'fail' } else { 'pass' }) -Detail ('探测 {0}/{1} 可解析，探针错误={2}，Chromium={3} CDP={4}' -f $found, $apps.Count, $probeErrors, (@($script:ProbeRows | Where-Object { $_.chromium }).Count), (@($script:ProbeRows | Where-Object { $_.cdp }).Count)) -DurationMs $sw.ElapsedMilliseconds
}

# ───────────────────────── 报告 ─────────────────────────

$script:RunStopwatch.Stop()
$commit = ''
try { $commit = (git -C $RepoRoot rev-parse --short HEAD 2>$null) } catch { }
$report = [pscustomobject]@{
    schema = 'winhand-benchmark/1'
    generated_at = (Get-Date).ToString('o')
    machine = [pscustomobject]@{
        os = (Get-CimInstance Win32_OperatingSystem).Caption + ' ' + (Get-CimInstance Win32_OperatingSystem).Version
        powershell = $PSVersionTable.PSVersion.ToString()
        host = $env:COMPUTERNAME
        user = $env:USERNAME
    }
    skill = [pscustomobject]@{
        repo = $RepoRoot
        commit = $commit
    }
    summary = [pscustomobject]@{
        pass = $script:PassCount
        fail = $script:FailCount
        skip = $script:SkipCount
        total = $script:Results.Count
        duration_ms = $script:RunStopwatch.ElapsedMilliseconds
    }
    scenarios = @($script:Results)
    probe_matrix = @($script:ProbeRows)
}

$jsonPath = Join-Path $OutDir 'report.json'
$mdPath = Join-Path $OutDir 'report.md'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = New-Object System.Collections.ArrayList
$md.Add('# winhand-use benchmark report') | Out-Null
$md.Add('') | Out-Null
$md.Add(('- 时间：{0}' -f $report.generated_at)) | Out-Null
$md.Add(('- 机器：{0} / PowerShell {1}' -f $report.machine.os, $report.machine.powershell)) | Out-Null
$md.Add(('- 技能提交：{0}' -f $commit)) | Out-Null
$md.Add(('- 汇总：{0} pass / {1} fail / {2} skip，总耗时 {3} ms' -f $report.summary.pass, $report.summary.fail, $report.summary.skip, $report.summary.duration_ms)) | Out-Null
$md.Add('') | Out-Null
$md.Add('| 场景 | 层 | 结果 | 耗时(ms) | 说明 |') | Out-Null
$md.Add('| --- | --- | --- | --- | --- |') | Out-Null
foreach ($s in $script:Results) {
    $md.Add(('| {0} | {1} | {2} | {3} | {4} |' -f $s.id, $s.layer, $s.status, $s.duration_ms, ($s.detail -replace '\|', '/'))) | Out-Null
}
if ($script:ProbeRows.Count -gt 0) {
    $md.Add('') | Out-Null
    $md.Add('## 常用软件探测矩阵') | Out-Null
    $md.Add('') | Out-Null
    $md.Add('| 应用 | 可解析 | 版本 | Chromium | CDP | 备注 |') | Out-Null
    $md.Add('| --- | --- | --- | --- | --- | --- |') | Out-Null
    foreach ($p in $script:ProbeRows) {
        $md.Add(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $p.app, $p.found, $p.version, $p.chromium, $p.cdp, $p.note)) | Out-Null
    }
}
$md -join "`r`n" | Set-Content -LiteralPath $mdPath -Encoding UTF8

Write-Host ''
Write-Host ('报告: ' + $mdPath)
Write-Host ('JSON: ' + $jsonPath)
Write-Host ('汇总: pass={0} fail={1} skip={2}' -f $script:PassCount, $script:FailCount, $script:SkipCount)
if ($script:FailCount -gt 0) { exit 1 }
exit 0
