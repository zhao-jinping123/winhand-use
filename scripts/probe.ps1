#!/usr/bin/env powershell
# probe.ps1 — 能力探测：接手任何 Windows app 前的第 0 步
# 用法: probe.ps1 <应用名|exe名|路径>    例: probe.ps1 剪映 / probe.ps1 notepad
# 只覆盖「静态 + L0 + L1」；输入/发送/借焦点/坑 探不到，实测后补进 references/app档案.md。

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Name = $args[0]
if (-not $Name) { Write-Output '用法: probe.ps1 <应用名|exe名|路径>'; exit 1 }

function Resolve-AppPath($name) {
    if (Test-Path $name) { return (Resolve-Path $name).Path }
    $proc = Get-Process | Where-Object { $_.ProcessName -like ('*' + $name + '*') -and $_.Path } | Select-Object -First 1
    if ($proc) { return $proc.Path }
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths'
    )
    foreach ($r in $roots) {
        if (Test-Path $r) {
            $key = Get-ChildItem $r | Where-Object { $_.PSChildName -like ('*' + $name + '*') } | Select-Object -First 1
            if ($key) {
                $v = (Get-ItemProperty $key.PSPath).'(default)'
                if ($v -and (Test-Path $v)) { return $v }
            }
        }
    }
    $lnkDirs = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory')
    )
    $shell = New-Object -ComObject WScript.Shell
    foreach ($d in $lnkDirs) {
        if (-not (Test-Path $d)) { continue }
        $lnks = @(Get-ChildItem $d -Filter *.lnk -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -like ('*' + $name + '*') })
        foreach ($lnk in $lnks) {
            $sc = $shell.CreateShortcut($lnk.FullName)
            if ($sc.TargetPath -and (Test-Path $sc.TargetPath)) { return $sc.TargetPath }
        }
    }
    return $null
}

$Path = Resolve-AppPath $Name
if (-not $Path) {
    Write-Output ('找不到应用「' + $Name + '」。给完整 exe 路径，或用 Get-Process 看进程名。')
    Write-Output '提示：显示名常对应英文 exe（剪映→JianyingPro，豆包→DoubaoWork）。'
    exit 1
}

$exeLeaf = Split-Path $Path -Leaf
$base = [IO.Path]::GetFileNameWithoutExtension($exeLeaf)
$vi = (Get-Item $Path).VersionInfo
$running = @(Get-Process | Where-Object { $_.ProcessName -eq $base })

Write-Output ('════ 静态 ════')
Write-Output ('路径: ' + $Path)
Write-Output ('exe: ' + $exeLeaf)
Write-Output ('版本: ' + $vi.FileVersion + '   # 核对档案第一步：版本变了档案坐标一律作废')
Write-Output ('运行中进程数: ' + $running.Count)
if ($running.Count -gt 0) {
    Write-Output ('pid: ' + (($running | Select-Object -First 5 | ForEach-Object { $_.Id }) -join ', '))
}

# ── L0 结构接口 ──
Write-Output ('════ L0 结构接口 ════')
$anyPid = $null
if ($running.Count -gt 0) { $anyPid = $running[0].Id }

# ① Chromium 系判定：同 exe 子进程带 --type= 渲染参数，或存在 crashpad_handler
$chromium = $false
if ($running.Count -gt 0) {
    $all = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq $exeLeaf -or ($anyPid -and $_.ParentProcessId -eq $anyPid)
    }
    $cmdlines = $all | ForEach-Object { $_.CommandLine }
    $renderer = @($cmdlines | Where-Object { $_ -match '--type=(renderer|gpu-process|utility)' })
    $crash = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like 'crashpad_handler*' -and $_.ExecutablePath -like ($Path.Split('\')[0..2] -join '\') + '*'
    })
    if ($renderer.Count -gt 0 -or $crash.Count -gt 0) { $chromium = $true }
}
Write-Output ('Chromium系(Electron/CEF): ' + $(if ($chromium) { '是 → 优先试 CDP' } else { '否' }))

# ② 监听端口（CDP / 本地服务）
if ($anyPid) {
    $ports = @(Get-NetTCPConnection -OwningProcess $anyPid -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty LocalPort -Unique)
    Write-Output ('监听端口: ' + $(if ($ports.Count -gt 0) { $ports -join ',' } else { '无' }))
    foreach ($p in $ports) {
        $ver = & curl.exe --noproxy '*' -s -m 2 "http://127.0.0.1:$p/json/version" 2>$null
        if ($ver -match 'webSocketDebuggerUrl|Browser') {
            Write-Output ('端口 ' + $p + ' = CDP ✅ 直接走 cdp.js，别碰坐标')
            $lines = $ver -split "`n" | Select-Object -First 3
            Write-Output ($lines -join "`n")
        } else {
            Write-Output ('端口 ' + $p + ' = 非 CDP（有本地服务，可试 JSON-RPC）')
        }
    }
} else {
    Write-Output '监听端口: app 未运行，无法探测（先 win open 再 probe）'
}

# ③ URL scheme（注册表反查，只扫相关子键避免全量枚举卡死）
$schemes = @()
$cmdKeys = @(
    'HKCU:\Software\Classes',
    'HKLM:\Software\Classes'
)
foreach ($hive in $cmdKeys) {
    if (-not (Test-Path $hive)) { continue }
    # 只看两类：名字与 exe 名相关；或数量可控的 HKCU 顶层键
    $kids = @(Get-ChildItem $hive -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -ne '*' -and $_.PSChildName -notlike 'AppX*' -and
        ($_.PSChildName -like ('*' + $base + '*') -or ($hive -like 'HKCU:*' -and $_.PSChildName -notmatch '^(\.|CLSID|Interface|Installer|TypeLib|WOW6432Node)'))
    } | Select-Object -First 400)
    foreach ($k in $kids) {
        $cmd = (Get-ItemProperty ($k.PSPath + '\shell\open\command') -ErrorAction SilentlyContinue).'(default)'
        if ($cmd -and $cmd -like ('*' + $base + '*')) { $schemes += $k.PSChildName }
    }
}
$schemes = @($schemes | Select-Object -Unique)
if ($schemes.Count -gt 0) {
    Write-Output ('URL scheme: ' + ($schemes -join ',') + '（注册了不等于能用，二进制里搜不到路由就别耗）')
} else {
    Write-Output 'URL scheme: 无/未查得'
}

# ④ CLI / 脚本接口提示（不自动执行，只报告存在性）
Write-Output ('自带CLI: 该 exe 的 --help/脚本接口需按 app 判断；Blender/Office 系常有（blender -b --python）')

# ── L1 UIA 语义树 ──
Write-Output ('════ L1 UIA ════')
if ($running.Count -gt 0) {
    $winPs1 = Join-Path $ScriptDir 'win.ps1'
    $axOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $winPs1 ax $anyPid 2>$null
    $summary = $axOut | Select-String -Pattern '^uia=on' | Select-Object -First 1
    if ($summary) {
        Write-Output $summary.ToString()
        $editable = [regex]::Match($summary.ToString(), 'editable=(\d+)').Groups[1].Value
        if ([int]$editable -gt 0) {
            Write-Output '可编辑控件 ≥1 → 先实测 axset 写 + 状态指示器变化，通了就全后台走'
        } else {
            Write-Output '可编辑控件 = 0 → UIA 大概率不可用（自绘/游戏/裸WebView），直接 L2 坐标'
        }
    } else {
        Write-Output 'UIA 树为空或 app 无窗口'
    }
} else {
    Write-Output 'app 未运行：UIA 需窗口，先 win open'
}

Write-Output ('════ 结论 ════')
if ($chromium) {
    Write-Output '路线建议: L0 CDP（零焦点）；开不了调试端口再考虑 UIA/坐标'
} else {
    Write-Output '路线建议: 有本地端口→CDP/JSON-RPC；UIA 通→后台写；都断→L2 坐标（win see + win op）'
}
Write-Output '把输出誊进 references/app档案.md（yaml 骨架见该文件），版本、坐标标实测日期。'
