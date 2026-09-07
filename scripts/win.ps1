#!/usr/bin/env powershell
# win.ps1 — winhand-use 操控内核（Windows PowerShell 5.1）
# 用法见 SKILL.md 命令表。所有命令输出 UTF-8。
# 首次运行会自动把 winuse.cs.inc 编译进 scripts\.cache\winuse.dll（约几秒），之后直加载。

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CacheDir = Join-Path $ScriptDir '.cache'
$SelfTickFile = Join-Path $env:TEMP 'winhand-use-selfinput.txt'

if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Output '内核需 Windows PowerShell 5.1（.NET Framework UIA），请用 powershell.exe -NoProfile -ExecutionPolicy Bypass -File win.ps1 调用'
    exit 1
}

# ---------- 编译 / 加载 C# 辅助层 ----------
function Initialize-Native {
    if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir | Out-Null }
    $cs = Join-Path $ScriptDir 'winuse.cs.inc'
    $dll = Join-Path $CacheDir 'winuse.dll'
    $needBuild = -not (Test-Path $dll)
    if (-not $needBuild) {
        $csTime = (Get-Item $cs).LastWriteTimeUtc
        $dllTime = (Get-Item $dll).LastWriteTimeUtc
        if ($csTime -gt $dllTime) { $needBuild = $true }
    }
    if ($needBuild) {
        $src = Get-Content $cs -Raw -Encoding UTF8
        # 先加载 WPF/UIA 程序集（GAC），再用真实 Location 作编译引用
        try { Add-Type -AssemblyName WindowsBase, PresentationCore, PresentationFramework, UIAutomationClient, UIAutomationTypes -ErrorAction SilentlyContinue } catch { }
        $clr = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
        $refs = @(
            (Join-Path $clr 'System.dll'),
            (Join-Path $clr 'System.Core.dll'),
            (Join-Path $clr 'System.Drawing.dll'),
            (Join-Path $clr 'System.Windows.Forms.dll'),
            (Join-Path $clr 'System.Xaml.dll'),
            [System.Windows.Point].Assembly.Location,
            [System.Windows.Media.Brushes].Assembly.Location,
            [System.Windows.Window].Assembly.Location,
            [System.Windows.Automation.AutomationElement].Assembly.Location,
            [System.Windows.Automation.ControlType].Assembly.Location
        )
        try {
            Add-Type -TypeDefinition $src -Language CSharp -ReferencedAssemblies $refs -OutputAssembly $dll -OutputType Library -ErrorAction Stop
        } catch {
            # 输出类型错误时退回无缓存编译，便于定位
            Write-Output ('编译失败（退回内存编译）: ' + $_.Exception.Message)
            Add-Type -TypeDefinition $src -Language CSharp -ReferencedAssemblies $refs -ErrorAction Stop
        }
    }
    Add-Type -Path $dll -ErrorAction Stop
}

# ---------- 自身合成输入痕迹 ----------
function Set-SelfTick {
    try { [WinUseNative]::LastInputTick() | Out-File -FilePath $SelfTickFile -Encoding ascii -Force } catch { }
}

function Get-SelfTick {
    if (Test-Path $SelfTickFile) {
        try { return [uint32](Get-Content $SelfTickFile -Raw).Trim() } catch { return 0 }
    }
    return 0
}

# ---------- 目标解析 ----------
function Write-Candidates($list) {
    $i = 0
    foreach ($w in $list) {
        $i++
        if ($i -gt 12) { Write-Output '…（候选太多，缩小关键词）'; break }
        Write-Host ('  ' + [WinUseNative]::WindowInfoLine($w))
    }
}

function Resolve-Target($target) {
    $script:WIN_EXIT = 0
    if (-not $target -or $target -eq '') { $script:WIN_EXIT = 2; return $null }
    if ($target -eq 'fg' -or $target -eq '前台') {
        $fg = [WinUseNative]::ForegroundHwnd()
        if ($fg -le 0) { Write-Output '前台无窗口（可能锁屏或安全桌面）'; $script:WIN_EXIT = 2; return $null }
        $list = [WinUseNative]::ListWindows('', $true)
        $hit = $list | Where-Object { $_.Hwnd.ToInt64() -eq $fg } | Select-Object -First 1
        return $hit
    }
    $list = [WinUseNative]::ListWindows('', $true)
    if ($target -match '^0x[0-9a-fA-F]+$') {
        $h = [Convert]::ToInt64($target.Substring(2), 16)
        $hit = $list | Where-Object { $_.Hwnd.ToInt64() -eq $h } | Select-Object -First 1
        if ($hit) { return $hit }
        Write-Host ('找不到 hwnd ' + $target + '（窗口已关闭？先 win windows 列一下）')
        $script:WIN_EXIT = 2; return $null
    }
    if ($target -match '^\d+$') {
        $pidNum = [uint32]$target
        $byPid = @($list | Where-Object { $_.Pid -eq $pidNum })
        if ($byPid.Count -eq 1) { return $byPid[0] }
        if ($byPid.Count -gt 1) {
            # 过滤 IME/隐藏/无尺寸窗口，尽量挑「真窗口」
            $main = @($byPid | Where-Object {
                $_.Title -notmatch '^(GDI|Default IME|MSCTFIME|主机弹出|TextInputHost)' -and
                $_.Rect.Width -gt 1 -and $_.Rect.Height -gt 1
            })
            if ($main.Count -eq 1) { return $main[0] }
            if ($main.Count -gt 1) {
                # 优先可见的
                $vis = @($main | Where-Object { $_.Visible })
                if ($vis.Count -eq 1) { return $vis[0] }
                if ($vis.Count -gt 1) {
                    Write-Host ('pid ' + $target + ' 有多个主窗口，用 hwnd 指定：')
                    Write-Candidates $vis
                    $script:WIN_EXIT = 2; return $null
                }
            }
            Write-Host ('pid ' + $target + ' 的窗口都是隐藏/无尺寸，用 hwnd 指定：')
            Write-Candidates $byPid
            $script:WIN_EXIT = 2; return $null
        }
        # pid 不存在窗口：可能是有窗口但枚举漏（被 shell 隐藏），兜底当 hwnd 十进制试
        $hit = $list | Where-Object { $_.Hwnd.ToInt64() -eq $pidNum } | Select-Object -First 1
        if ($hit) { return $hit }
        Write-Host ('找不到 pid/窗口 ' + $target + '（进程没开窗？用 win open 启动）')
        $script:WIN_EXIT = 2; return $null
    }
    $hits = @($list | Where-Object {
        $_.Owner -like ('*' + $target + '*') -or $_.Title -like ('*' + $target + '*')
    })
    if ($hits.Count -eq 0) {
        # 进程可能开着但没窗口，给进程列表提示
        Write-Host ('关键词「' + $target + '」没匹配到任何窗口。列一下近似进程：')
        Get-Process | Where-Object { $_.ProcessName -like ('*' + $target + '*') } |
            Select-Object -First 10 | ForEach-Object { Write-Output ('  进程 ' + $_.ProcessName + ' pid=' + $_.Id) }
        Write-Host '（该 app 可能没开窗口：先 win open，或加 --all 看看隐藏窗口）'
        $script:WIN_EXIT = 2; return $null
    }
    if ($hits.Count -eq 1) { return $hits[0] }
    Write-Host ('关键词「' + $target + '」命中多个窗口，用 hwnd 指定：')
    Write-Candidates $hits
    $script:WIN_EXIT = 2; return $null
}

# ---------- 应用启动器 ----------
function Resolve-AppPath($name) {
    if (Test-Path $name) { return (Resolve-Path $name).Path }
    # ① 运行中进程
    $proc = Get-Process | Where-Object { $_.ProcessName -like ('*' + $name + '*') -and $_.Path } | Select-Object -First 1
    if ($proc) { return $proc.Path }
    # ② App Paths 注册表（HKLM+HKCU）
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
    # ③ 开始菜单 + 桌面快捷方式（中文显示名靠文件名）
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
            Where-Object { $_.BaseName -like ('*' + $name + '*') -or $_.Name -like ('*' + $name + '*') })
        foreach ($lnk in $lnks) {
            $sc = $shell.CreateShortcut($lnk.FullName)
            if ($sc.TargetPath -and (Test-Path $sc.TargetPath)) { return $sc.TargetPath }
        }
    }
    # ④ 常见安装目录兜底：直接按 exe 文件名全盘搜常见目录（限两层）
    $exe = $name
    if (-not $exe.EndsWith('.exe')) { $exe = $exe + '.exe' }
    $dirs = @('C:\Program Files', 'C:\Program Files (x86)', (Join-Path $env:LOCALAPPDATA 'Programs'))
    foreach ($d in $dirs) {
        if (Test-Path $d) {
            $hit = Get-ChildItem $d -Filter $exe -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

# ---------- 在场 / 闸 ----------
function Test-Presence {
    # 返回 'ok'（用户没在动）或等待后 'ok'，超时返回 'blocked:用户一直在动'
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ($true) {
        $idle = [WinUseNative]::IdleMilliseconds()
        $self = Get-SelfTick
        $now = [WinUseNative]::LastInputTick()
        if ($self -gt 0 -and ($now - [uint64]$self) -lt 1200) {
            # 最近的输入是我们自己合成的，排除
            return 'ok'
        }
        if ($idle -ge 2000) { return 'ok' }
        if ([DateTime]::UtcNow -gt $deadline) { return 'blocked:用户2秒内动过键鼠，等了15秒仍在动，拒绝抢焦点' }
        Start-Sleep -Milliseconds 500
    }
}

function Show-GateReport($name, $state, $detail) {
    Write-Host ('闸[' + $name + ']=' + $state + '  ' + $detail)
}

# 借焦点执行：四道闸 + HUD + 还原。$action 是 scriptblock，参数 $hwnd
function Invoke-FocusAction($info, $action, $force, $dry) {
    $hwnd = $info.Hwnd
    $fgBeforeHwnd = [WinUseNative]::ForegroundHwnd()
    $fgBefore = [WinUseNative]::ForegroundInfo()
    $curPos = [System.Windows.Forms.Cursor]::Position

    # 闸1 在场
    if (-not $force) {
        $p = Test-Presence
        Show-GateReport '在场' $(if ($p -eq 'ok') { 'pass' } else { 'BLOCK' }) $p
        if ($p -ne 'ok') { return 2 }
    } else {
        Show-GateReport '在场' 'force' '--force 已拆'
    }
    # 闸2 焦点锁
    if (-not $force) {
        if ([WinUseNative]::TryAcquireFocusLock()) {
            Show-GateReport '焦点锁' 'pass' '拿到全机借焦点锁'
        } else {
            Show-GateReport '焦点锁' 'BLOCK' '已有别的进程在借焦点'
            return 2
        }
    }
    try {
        if ($dry) {
            Show-GateReport '前台' 'dry' '目标窗口当前不在前台；dry 模式不实际借焦点。预演通过'
            return 0
        }
        # HUD（默认开；WIN_HUD=0 关闭）
        if ($env:WIN_HUD -ne '0') {
            [WinUseNative]::ShowHud(1000, 'agent 正在操作窗口，很快归还')
        }
        $ok = [WinUseNative]::BringToFront($hwnd)
        Show-GateReport '前台' $(if ($ok) { 'pass' } else { 'FAIL' }) $(if ($ok) { '已把目标带到前台' } else { 'SetForegroundWindow 失败（窗口被系统/全屏独占挡住？）' })
        if (-not $ok) {
            # 再试一次 ShowWindow + SetForegroundWindow
            Start-Sleep -Milliseconds 300
            $ok = [WinUseNative]::BringToFront($hwnd)
        }
        if (-not $ok) {
            Write-Host 'result=refused 借焦点失败。可能原因：agent 在无交互会话、窗口跨虚拟桌面、或全屏独占。请把窗口挪到当前桌面后重试。'
            return 2
        }
        Start-Sleep -Milliseconds 250
        & $action $hwnd
        Set-SelfTick
    } finally {
        [WinUseNative]::ReleaseFocusLock()
        # 还原前台与鼠标
        try {
            if ($fgBeforeHwnd -gt 0) { [WinUseNative]::RestoreForeground([IntPtr]$fgBeforeHwnd) | Out-Null }
            [System.Windows.Forms.Cursor]::Position = $curPos
        } catch { }
    }
    return 0
}

function Invoke-Hud($ms, $text) {
    if ($env:WIN_HUD -ne '0') {
        try { [WinUseNative]::ShowHud($ms, $text) } catch { }
    }
}

# ---------- 截图辅助 ----------
function New-TempShot($tag) {
    return Join-Path $env:TEMP ('huashu-win-' + $tag + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.png')
}

function Write-ShotResult($result, $analysis, $path, $prefix) {
    Write-Output ($prefix + 'shot=' + $result)
    if ($analysis -match '^size=(\d+)x(\d+) black=([\d.]+) white=([\d.]+) colors=(\d+)$') {
        Write-Output ($prefix + 'size=' + $Matches[1] + 'x' + $Matches[2] + ' black=' + $Matches[3] + ' white=' + $Matches[4] + ' colors=' + $Matches[5])
        $black = [double]$Matches[3]; $colors = [int]$Matches[5]
        if ($black -gt 0.98 -and $colors -lt 4) {
            Write-Output ($prefix + '判定=疑似空图/黑屏（后台渲染不上？用 shotfg 或确认窗口非最小化）')
        }
    }
    Write-Output ($prefix + 'path=' + $path)
}

# ---------- 坐标换算 ----------
# 输入 x y 可为：<=1 归一化 / >1 窗口 rect 像素 / @图后缀（图上像素按图与窗口尺寸等比）
function Convert-Coords($xRaw, $yRaw, $imgPath, $info) {
    $wRect = $info.Rect.Width; $hRect = $info.Rect.Height
    $x = [double]$xRaw; $y = [double]$yRaw
    if ($imgPath) {
        $img = [System.Drawing.Image]::FromFile((Resolve-Path $imgPath).Path)
        try {
            if ($img.Width -gt 0 -and $wRect -gt 0) { $x = $x * $wRect / $img.Width }
            if ($img.Height -gt 0 -and $hRect -gt 0) { $y = $y * $hRect / $img.Height }
        } finally { $img.Dispose() }
    }
    if ($x -le 1.0 -and $y -le 1.0) {
        $x = $x * $wRect; $y = $y * $hRect
        Write-Host '坐标=归一化（按窗口尺寸换算）'
    } else {
        Write-Host ('坐标=窗口rect像素 (' + [int]$x + ',' + [int]$y + ') 窗口 ' + $wRect + 'x' + $hRect)
    }
    return @([int][Math]::Round($x), [int][Math]::Round($y))
}

$script:WIN_EXIT = 0   # 退出码三态：0 成功 / 1 失败 / 2 拒绝或未知（agent 框架靠它判断）
Initialize-Native
[WinUseNative]::MakeDpiAware()   # DPI aware：窗口 rect 与截图同为物理像素
Add-Type -AssemblyName System.Drawing, System.Windows.Forms -ErrorAction SilentlyContinue   # 供 Convert-Coords / Cursor 使用

$cmd = $args[0]
$rest = @($args | Select-Object -Skip 1)

switch ($cmd) {
    # ---------- win windows [关键词] [--all] ----------
    'windows' {
        $kw = ''; $all = $false
        foreach ($t in $rest) {
            if ($t -eq '--all') { $all = $true } elseif ($kw -eq '') { $kw = $t }
        }
        $list = [WinUseNative]::ListWindows($kw, $all)
        Write-Output ('窗口数=' + $list.Count)
        foreach ($w in $list) { Write-Output ([WinUseNative]::WindowInfoLine($w)) }
        break
    }

    # ---------- win fg ----------
    'fg' {
        Write-Output ([WinUseNative]::ForegroundInfo())
        Write-Output ('idle_ms=' + [WinUseNative]::IdleMilliseconds())
        break
    }

    # ---------- win idle ----------
    'idle' {
        $idle = [WinUseNative]::IdleMilliseconds()
        Write-Output ('键鼠空闲=' + [math]::Round($idle / 1000.0, 1) + ' 秒')
        Write-Output ([WinUseNative]::ForegroundInfo())
        $held = -not [WinUseNative]::TryAcquireFocusLock()
        if ($held) {
            Write-Output '焦点锁=被占用'
        } else {
            Write-Output '焦点锁=空闲'
            [WinUseNative]::ReleaseFocusLock()
        }
        Write-Output ('self_tick=' + (Get-SelfTick))
        break
    }

    # ---------- win open <名字|路径> [--cdp 9333] [--relaunch] [--args ...] ----------
    'open' {
        $name = $rest[0]
        if (-not $name) { Write-Output '用法: win open <应用名|exe路径> [--cdp <端口>] [--relaunch] [--arg <参数>...]'; break }
        $cdp = $null; $relaunch = $false; $appArgs = @()
        for ($i = 1; $i -lt $rest.Count; $i++) {
            if ($rest[$i] -eq '--cdp') { $cdp = $rest[++$i] }
            elseif ($rest[$i] -eq '--relaunch') { $relaunch = $true }
            elseif ($rest[$i] -eq '--arg') { $appArgs += $rest[++$i] }
        }
        $path = Resolve-AppPath $name
        if (-not $path) {
            $script:WIN_EXIT = 1
            Write-Output ('找不到应用「' + $name + '」。给完整 exe 路径，或先确认它已安装。')
            Write-Output '提示：Win 上的「显示名」常对应英文 exe（剪映→JianyingPro，豆包→DoubaoWork）；请用 Get-Process / 开始菜单名核对。'
            break
        }
        $exeName = Split-Path $path -Leaf
        if ($relaunch) {
            $running = @(Get-Process | Where-Object { $_.ProcessName -eq ([IO.Path]::GetFileNameWithoutExtension($exeName)) })
            if ($running.Count -gt 0) {
                Write-Output ('--relaunch: 将关闭 ' + $running.Count + ' 个进程（未保存内容可能丢失）：')
                $running | ForEach-Object { Write-Output ('  关闭 pid=' + $_.Id + ' ' + $_.ProcessName) }
                $running | Stop-Process -Force
                Start-Sleep -Milliseconds 800
            }
        }
        if ($cdp) {
            $appArgs += '--remote-debugging-port=' + $cdp
            $appArgs += '--remote-allow-origins=*'
        }
        Write-Output ('启动: ' + $path + ' ' + ($appArgs -join ' '))
        Start-Process -FilePath $path -ArgumentList $appArgs | Out-Null
        Start-Sleep -Seconds 1
        $proc = Get-Process | Where-Object { $_.ProcessName -eq ([IO.Path]::GetFileNameWithoutExtension($exeName)) -and $_.Path } |
            Sort-Object StartTime -Descending | Select-Object -First 1
        if ($proc) {
            Write-Output ('pid=' + $proc.Id)
        } else {
            Write-Output '已发出启动请求（进程未能在1秒内确认，稍等后 win windows 查）'
        }
        if ($cdp) {
            # 等调试端口起来
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep -Milliseconds 500
                $ok = & curl.exe --noproxy '*' -s -m 2 "http://127.0.0.1:$cdp/json/version" 2>$null
                if ($ok -match 'webSocketDebuggerUrl|Browser') {
                    Write-Output ('cdp=ready ' + $ok)
                    break
                }
            }
        }
        break
    }

    # ---------- win shot <目标> <png> [--fg] ----------
    'shot' {
        if ($rest.Count -lt 2) { Write-Output '用法: win shot <目标|hwnd|pid> <输出.png> [--fg]'; break }
        $info = Resolve-Target $rest[0]
        if (-not $info) { break }
        $path = $rest[1]
        $fgMode = $rest -contains '--fg'
        if ($fgMode) {
            # shotfg 逻辑：先后台，空/失败才借焦点
            $r1 = [WinUseNative]::PrintWindowToFile($info.Hwnd, $path)
            $a1 = [WinUseNative]::AnalyzePng($path)
            if ($r1 -like 'ok*' -and $a1 -notmatch 'black=1.000' -and $a1 -match 'colors=(\d+)' -and [int]$Matches[1] -gt 3) {
                Write-ShotResult $r1 $a1 $path '后台'
                break
            }
            Write-Output ('后台截图不可用（' + $r1 + ' / ' + $a1 + '），借焦点前台截…')
            $rv = Invoke-FocusAction $info { param($h) [WinUseNative]::CaptureForegroundRect($h, $path) } $false $false
            if ($rv -eq 0) {
                $a2 = [WinUseNative]::AnalyzePng($path)
                Write-ShotResult 'ok(前台)' $a2 $path '借焦点'
            }
        } else {
            $r = [WinUseNative]::PrintWindowToFile($info.Hwnd, $path)
            $a = [WinUseNative]::AnalyzePng($path)
            Write-ShotResult $r $a $path '后台'
            if ($r -notlike 'ok*') { $script:WIN_EXIT = 1 }
        }
        break
    }

    # ---------- win hud <毫秒> [文案] ----------
    'hud' {
        $ms = if ($rest[0]) { [int]$rest[0] } else { 1500 }
        $text = if ($rest.Count -gt 1) { ($rest[1..($rest.Count - 1)] -join ' ') } else { 'agent 正在操作' }
        [WinUseNative]::ShowHud($ms, $text)
        Write-Output 'hud=shown'
        break
    }

    # ---------- win see <目标> [--out <目录>] ----------
    'see' {
        $target = $rest[0]
        if (-not $target) { Write-Output '用法: win see <目标> [--out <目录>]'; break }
        $info = Resolve-Target $target
        if (-not $info) { break }
        $outDir = $null
        for ($i = 1; $i -lt $rest.Count; $i++) {
            if ($rest[$i] -eq '--out') { $outDir = $rest[++$i] }
        }
        if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        $safeName = ($info.Owner + '-' + $info.Pid) -replace '[^\w\-]', '_'
        $shotPath = if ($outDir) { Join-Path $outDir ($safeName + '.png') } else { New-TempShot 'see' }
        $r = [WinUseNative]::PrintWindowToFile($info.Hwnd, $shotPath)
        Write-Output ('目标: ' + [WinUseNative]::WindowInfoLine($info))
        $a = [WinUseNative]::AnalyzePng($shotPath)
        Write-ShotResult $r $a $shotPath 'see='
        Write-Output '--- UIA 摘要（可交互元素，前 60 个）---'
        $scan = [WinUseNative]::UiScan($info.Hwnd, '', 60)
        Write-Output $scan.TrimEnd("`r`n")
        Write-Output '--- 提示：坐标按上图窗口像素；先看 UIA 能否直接用（eN 编号见 ax 输出）---'
        break
    }

    # ---------- win ax <目标> [关键词] ----------
    'ax' {
        $target = $rest[0]
        if (-not $target) { Write-Output '用法: win ax <目标> [关键词]'; break }
        $info = Resolve-Target $target
        if (-not $info) { break }
        $kw = if ($rest.Count -gt 1) { $rest[1] } else { '' }
        Write-Output ([WinUseNative]::UiScan($info.Hwnd, $kw, 120).TrimEnd("`r`n"))
        break
    }

    # ---------- win axset <目标> <eN|path|关键词> <文本> ----------
    'axset' {
        if ($rest.Count -lt 3) { Write-Output '用法: win axset <目标> <e0|0/1/2|关键词|-> <文本>'; break }
        $info = Resolve-Target $rest[0]
        if (-not $info) { break }
        $sel = $rest[1]
        $text = ($rest[2..($rest.Count - 1)] -join ' ')
        $rb = ''
        $res = [WinUseNative]::UiSetValueSmart($info.Hwnd, $sel, $text, [ref]$rb)
        Write-Output ('axset=' + $res)
        Write-Output ('readback=' + $rb)
        if ($res -like 'ok*' -and $rb -eq $text) { Write-Output 'effect=confirmed(UIA读回一致)' }
        elseif ($res -like 'ok*') { Write-Output 'effect=partial(读回不一致，可能暗拒——看发送键/状态指示器，不行就 op 借焦点)' }
        else { Write-Output 'effect=failed'; $script:WIN_EXIT = 1 }
        break
    }

    # ---------- win type <目标> <文本> [--bg] ----------
    'type' {
        if ($rest.Count -lt 2) { Write-Output '用法: win type <目标> <文本> [--bg]'; break }
        $info = Resolve-Target $rest[0]
        if (-not $info) { break }
        $bg = $rest -contains '--bg'
        $text = ($rest | Where-Object { $_ -ne '--bg' } | Select-Object -Skip 1) -join ' '
        if ($bg) {
            # 后台档：UIA 直写第一个可编辑控件（对应 mac 的 postToPid/AX 后台档）
            $rb = ''
            $res = [WinUseNative]::UiSetValueSmart($info.Hwnd, '', $text, [ref]$rb)
            Write-Output ('type--bg=' + $res)
            Write-Output ('readback=' + $rb)
            if ($res -like 'ok*' -and $rb -eq $text) { Write-Output 'effect=confirmed' }
            elseif ($res -like 'ok*') { Write-Output 'effect=partial(读回不一致，可能暗拒)' }
            else { Write-Output 'effect=failed（后台档只对 UIA 可编辑控件有效；用 win op 会按坐标点击+借焦点）'; $script:WIN_EXIT = 1 }
            break
        }
        # 全局档：要求目标已在前台（frontmost 闸），否则拒绝，别硬抢
        $fg = [WinUseNative]::ForegroundHwnd()
        if ($fg -ne $info.Hwnd.ToInt64()) {
            $script:WIN_EXIT = 2
            Write-Output 'refused: 前台不是目标窗口（type 全局档打给当前前台）。'
            Write-Output ('当前前台: ' + [WinUseNative]::ForegroundInfo())
            Write-Output '出路：win op <目标> <x> <y> <文本>（自动借焦点）；或先让目标到前台。'
            break
        }
        $p = Test-Presence
        Show-GateReport '在场' $(if ($p -eq 'ok') { 'pass' } else { 'BLOCK' }) $p
        if ($p -ne 'ok') { break }
        [WinUseNative]::TypeUnicodeText($text)
        Set-SelfTick
        Write-Output 'type=ok(全局 Unicode 键入，逐字不依赖键盘布局，中文/emoji 可用)'
        Write-Output 'effect=待验证（截图看字 + 看发送键/状态指示器，别信工具返回）'
        break
    }

    # ---------- win key <目标> <键> [--bg] ----------
    'key' {
        if ($rest.Count -lt 2) { Write-Output '用法: win key <目标> <Enter|Esc|Tab|Backspace|Del|方向键|F5|ctrl+c|…> [--bg]'; break }
        $info = Resolve-Target $rest[0]
        if (-not $info) { break }
        $keyArg = $rest[1]
        $bg = $rest -contains '--bg'
        $map = @{
            'Enter' = 13; 'Return' = 13; 'Esc' = 27; 'Escape' = 27; 'Tab' = 9; 'Backspace' = 8; 'BS' = 8;
            'Delete' = 46; 'Del' = 46; 'Space' = 32; 'Up' = 38; 'Down' = 40; 'Left' = 37; 'Right' = 39;
            'Home' = 36; 'End' = 35; 'PageUp' = 33; 'PageDown' = 34; 'F5' = 116; 'F6' = 117
        }
        $ctrl = $false; $shift = $false; $alt = $false; $vk = $null
        $parts = $keyArg -split '\+'
        foreach ($p in $parts) {
            $pl = $p.ToLowerInvariant()
            if ($pl -eq 'ctrl' -or $pl -eq 'control') { $ctrl = $true }
            elseif ($pl -eq 'shift') { $shift = $true }
            elseif ($pl -eq 'alt') { $alt = $true }
            elseif ($map.ContainsKey($p)) { $vk = $map[$p] }
            elseif ($p.Length -eq 1 -and $p -match '[a-zA-Z0-9]') { $vk = [int][char]($p.ToUpperInvariant()) }
            elseif ($p.Length -eq 1 -and $p -match '[.,/;\\\[\]-]') { $vk = [int][char]$p }
        }
        if (-not $vk) { Write-Output ('不识别的键: ' + $keyArg); break }
        if ($bg) {
            # 后台档：直接 PostMessage 到窗口（对原生按钮/编辑框有效；自绘/Chromium 大概率无效）
            $l = [IntPtr]::Zero
            [WinUseNative]::PostMessage($info.Hwnd, 0x100, [IntPtr]$vk, $l) | Out-Null   # WM_KEYDOWN
            [WinUseNative]::PostMessage($info.Hwnd, 0x101, [IntPtr]$vk, $l) | Out-Null   # WM_KEYUP
            Write-Output 'key--bg=posted(PostMessage；自绘控件可能无效，截图验证)'
            break
        }
        $fg = [WinUseNative]::ForegroundHwnd()
        if ($fg -ne $info.Hwnd.ToInt64()) {
            $script:WIN_EXIT = 2
            Write-Output 'refused: 前台不是目标窗口（key 全局档打给当前前台）。用 win op / 先把目标放前台。'
            break
        }
        $p = Test-Presence
        if ($p -ne 'ok') { Show-GateReport '在场' 'BLOCK' $p; break }
        [WinUseNative]::TypeKey([int]$vk, $ctrl, $shift, $alt)
        Set-SelfTick
        Write-Output ('key=ok vk=' + $vk + ' ctrl=' + $ctrl + ' shift=' + $shift)
        break
    }

    # ---------- win click/op 公共解析 ----------
    'click' {
        # 用法: win click <目标> <x> <y> [@图] [--dry|--bg|--fast|--force]
        if ($rest.Count -lt 3) { Write-Output '用法: win click <目标> <x> <y> [@图] [--dry|--bg|--fast|--force]'; break }
        $info = Resolve-Target $rest[0]
        if (-not $info) { break }
        $xRaw = $rest[1]; $yRaw = $rest[2]
        $img = $null
        $dry = $rest -contains '--dry'; $bg = $rest -contains '--bg'
        $fast = $rest -contains '--fast'; $force = $rest -contains '--force'
        for ($i = 3; $i -lt $rest.Count; $i++) {
            if ($rest[$i] -match '^@(.+)$') { $img = $Matches[1] }
            elseif ($rest[$i] -match '\.(png|jpg|jpeg)$') { $img = $rest[$i] }
        }
        if ($xRaw -match '^([\d.]+),([\d.]+)(?:@(.+))?$') {
            $xRaw = $Matches[1]; $yRaw = $Matches[2]
            if ($Matches[3]) { $img = $Matches[3] }
        }
        if ($yRaw -match '^([\d.]+),([\d.]+)(?:@(.+))?$') {
            $yRaw = $Matches[2]; if ($Matches[3]) { $img = $Matches[3] }
        }
        $xy = Convert-Coords $xRaw $yRaw $img $info
        $rx = $xy[0]; $ry = $xy[1]
        $rect = $info.Rect
        $screenX = $rect.Left + $rx; $screenY = $rect.Top + $ry
        $cc = [WinUseNative]::ConvertToClient($info.Hwnd, $rx, $ry)
        if ($cc -eq 'fail') { Write-Output '坐标换算失败'; break }
        $cx = [int]($cc.Split(' ')[0]); $cy = [int]($cc.Split(' ')[1])
        Write-Output ('client=(' + $cx + ',' + $cy + ') screen=(' + $screenX + ',' + $screenY + ')')
        $before = New-TempShot 'click-before'
        $after = New-TempShot 'click-after'
        [WinUseNative]::PrintWindowToFile($info.Hwnd, $before) | Out-Null
        if ($dry) {
            Write-Output '--dry 预演：'
            Show-GateReport '前台' $(if ([WinUseNative]::IsForeground($info.Hwnd)) { 'pass(已在前台)' } else { '需借焦点' }) '见下'
            $p = Test-Presence
            Show-GateReport '在场' $(if ($p -eq 'ok') { 'pass' } else { 'BLOCK' }) $p
            Show-GateReport '遮挡' '见参考' ('落点最上层: ' + [WinUseNative]::TopWindowAt($screenX, $screenY))
            break
        }
        $clicked = $false
        if (-not $fast) {
            # 后台档
            $post = [WinUseNative]::PostClick($info.Hwnd, $cx, $cy, $false)
            Start-Sleep -Milliseconds 250
            $clicked = $true
            Write-Output ('后台档: ' + $post)
        }
        if ($fast -or $force -or (-not $bg -and $clicked)) {
            [WinUseNative]::PrintWindowToFile($info.Hwnd, $after) | Out-Null
            $diff = [WinUseNative]::DiffPngs($before, $after)
            Write-Output ('后台档差分: ' + $diff)
            $changed = if ($diff -match 'changed=([\d.]+)') { [double]$Matches[1] } else { 0 }
            if ($changed -lt 0.001 -and -not $bg -and -not $fast) {
                # 升级借焦点（真实点击）
                Write-Output '后台点击疑似无效（界面无变化），升级借焦点做真实点击…'
                $okClick = $false
                $rv = Invoke-FocusAction $info {
                    param($h)
                    [WinUseNative]::GlobalClick($screenX, $screenY)
                    Set-SelfTick
                } $force $false
                if ($rv -eq 2) { $script:WIN_EXIT = 2 }
                if ($rv -eq 0) { $okClick = $true }
            }
        }
        if ($fast) {
            $okClick = $false
            $rv = Invoke-FocusAction $info { param($h) [WinUseNative]::GlobalClick($screenX, $screenY) } $force $false
            if ($rv -eq 2) { $script:WIN_EXIT = 2 }
            if ($rv -eq 0) { $okClick = $true }
        }
        Start-Sleep -Milliseconds 300
        [WinUseNative]::PrintWindowToFile($info.Hwnd, $after) | Out-Null
        $diff2 = [WinUseNative]::DiffPngs($before, $after)
        Write-Output ('最终差分: ' + $diff2)
        $chg = if ($diff2 -match 'changed=([\d.]+)') { [double]$Matches[1] } else { -1 }
        if ($chg -ge 0.001) { Write-Output 'effect=confirmed(界面有变化)' }
        elseif ($chg -ge 0) { Write-Output 'effect=suspected_noop(差分≈0。不是失败，回去重看：窗口可能被遮挡/点到了空白/按钮 hover 无痕)' }
        else { Write-Output 'effect=unverifiable(截图失败)' }
        Remove-Item $before, $after -ErrorAction SilentlyContinue
        break
    }

    'op' {
        # 用法: win op <目标> <x> <y> <文本> [@图] [--dry|--bg|--fast|--force]
        if ($rest.Count -lt 4) { Write-Output '用法: win op <目标> <x> <y> <文本> [@图] [--dry|--bg|--fast|--force]'; break }
        $info = Resolve-Target $rest[0]
        if (-not $info) { break }
        $xRaw = $rest[1]; $yRaw = $rest[2]
        $flags = @('--dry', '--bg', '--fast', '--force')
        $dry = $false; $bg = $false; $fast = $false; $force = $false
        foreach ($f in $flags) { if ($rest -contains $f) { Set-Variable -Name ($f.Substring(2)) -Value $true } }
        $img = $null
        $textParts = @()
        for ($i = 3; $i -lt $rest.Count; $i++) {
            if ($rest[$i] -in $flags) { continue }
            elseif ($rest[$i] -match '^@(.+)$') { $img = $Matches[1] }
            elseif ($rest[$i] -match '\.(png|jpg|jpeg)$') { $img = $rest[$i] }
            else { $textParts += $rest[$i] }
        }
        if ($xRaw -match '^([\d.]+),([\d.]+)(?:@(.+))?$') {
            $xRaw = $Matches[1]; $yRaw = $Matches[2]; if ($Matches[3]) { $img = $Matches[3] }
        }
        if ($yRaw -match '^([\d.]+),([\d.]+)(?:@(.+))?$') {
            $yRaw = $Matches[2]; if ($Matches[3]) { $img = $Matches[3] }
        }
        $text = $textParts -join ' '
        $xy = Convert-Coords $xRaw $yRaw $img $info
        $rx = $xy[0]; $ry = $xy[1]
        $rect = $info.Rect
        $screenX = $rect.Left + $rx; $screenY = $rect.Top + $ry
        $cc = [WinUseNative]::ConvertToClient($info.Hwnd, $rx, $ry)
        if ($cc -eq 'fail') { Write-Output '坐标换算失败'; break }
        $cx = [int]($cc.Split(' ')[0]); $cy = [int]($cc.Split(' ')[1])
        Write-Output ('client=(' + $cx + ',' + $cy + ') screen=(' + $screenX + ',' + $screenY + ')')
        $before = New-TempShot 'op-before'
        $after = New-TempShot 'op-after'
        [WinUseNative]::PrintWindowToFile($info.Hwnd, $before) | Out-Null
        if ($dry) {
            Write-Output '--dry 预演（不执行）：'
            $ptEl = [WinUseNative]::ElementAtPoint($screenX, $screenY)
            Write-Output ('落点元素: ' + $ptEl)
            Show-GateReport '后台档' '可用' ('PostClick + ' + $(if ($ptEl -match 'ControlType\.(Edit|Document)') { 'UIA 直写文本' } else { '无 UIA 编辑控件，文本需借焦点键入' }))
            Show-GateReport '在场' '见下' $(Test-Presence)
            Show-GateReport '遮挡' '见下' ('落点最上层: ' + [WinUseNative]::TopWindowAt($screenX, $screenY))
            Write-Output '预演完成（零执行）。'
            break
        }
        # 1) 后台档
        if (-not $fast) {
            [WinUseNative]::PostClick($info.Hwnd, $cx, $cy, $false) | Out-Null
            Start-Sleep -Milliseconds 200
            if ($text) {
                $ptEl = [WinUseNative]::ElementAtPoint($screenX, $screenY)
                Write-Output ('落点元素: ' + $ptEl)
                if ($ptEl -match 'ControlType\.(Edit|Document)') {
                    $rb = ''
                    $ures = [WinUseNative]::UiSetValueAtPoint($screenX, $screenY, $text, [ref]$rb)
                    Write-Output ('UIA直写: ' + $ures + ' readback=' + $rb)
                    if ($ures -like 'ok*' -and $rb -eq $text) {
                        Write-Output 'effect=confirmed(UIA 写通，未借焦点)'
                        [WinUseNative]::PrintWindowToFile($info.Hwnd, $after) | Out-Null
                        Write-Output ('差分: ' + [WinUseNative]::DiffPngs($before, $after))
                        Remove-Item $before, $after -ErrorAction SilentlyContinue
                        break
                    }
                } else {
                    Write-Output '落点不是 UIA 可编辑控件，文本将走借焦点键入'
                }
            }
            # 纯点击验证
            Start-Sleep -Milliseconds 200
            [WinUseNative]::PrintWindowToFile($info.Hwnd, $after) | Out-Null
            $d1 = [WinUseNative]::DiffPngs($before, $after)
            Write-Output ('后台档差分: ' + $d1)
            if ($d1 -match 'changed=([\d.]+)' -and [double]$Matches[1] -ge 0.001 -and -not $text) {
                Write-Output 'effect=confirmed(点击后界面有变化)'
                Remove-Item $before, $after -ErrorAction SilentlyContinue
                break
            }
        }
        # 2) 升级借焦点（真实点击 + 键入）
        if (-not $bg) {
            Write-Output '升级借焦点…'
            $rv = Invoke-FocusAction $info {
                param($h)
                [WinUseNative]::GlobalClick($screenX, $screenY)
                if ($text) {
                    Start-Sleep -Milliseconds 150
                    [WinUseNative]::TypeUnicodeText($text)
                }
                Set-SelfTick
            } $force $false
            if ($rv -ne 0) {
                $script:WIN_EXIT = 2
                Write-Output 'effect=unverifiable(借焦点被拒)'
                Remove-Item $before, $after -ErrorAction SilentlyContinue
                break
            }
            Start-Sleep -Milliseconds 400
            [WinUseNative]::PrintWindowToFile($info.Hwnd, $after) | Out-Null
            $d2 = [WinUseNative]::DiffPngs($before, $after)
            Write-Output ('借焦点后差分: ' + $d2)
            $chg = if ($d2 -match 'changed=([\d.]+)') { [double]$Matches[1] } else { -1 }
            if ($chg -ge 0.001) { Write-Output 'effect=confirmed(界面有变化)' }
            elseif ($chg -ge 0) { Write-Output 'effect=suspected_noop(差分≈0。回去重看：字是否进去、发送键是否变亮，别信工具返回)' }
            else { Write-Output 'effect=unverifiable(截图失败)' }
        } else {
            Write-Output 'effect=suspected_noop(--bg 模式，后台无效就停在这，不抢焦点)'
        }
        Remove-Item $before, $after -ErrorAction SilentlyContinue
        break
    }

    # ---------- win axpress <目标> <eN|path|关键词>：UIA Invoke 后台触发（零焦点，对应 mac 版 AXPress） ----------
    'axpress' {
        if ($rest.Count -lt 2) {
            Write-Output '用法: win axpress <目标> <eN|path|关键词>'
            $script:WIN_EXIT = 1
            break
        }
        $info = Resolve-Target $rest[0]
        if (-not $info) { break }
        $sel = $rest[1]
        $res = [WinUseNative]::UiInvokeSmart($info.Hwnd, $sel)
        Write-Output ('axpress=' + $res)
        if ($res -like 'ok*') {
            Write-Output 'effect=已触发（UIA Invoke 不抢焦点；web view 可能假成功，照常用截图/副作用验证）'
        } else {
            Write-Output 'effect=failed'
            $script:WIN_EXIT = 1
        }
        break
    }

    # ---------- win doctor：任何 runtime 首次使用前的环境自检 ----------
    'doctor' {
        Write-Output ('os=' + [Environment]::OSVersion.VersionString)
        Write-Output ('ps=' + $PSVersionTable.PSVersion.ToString() + ' edition=' + $PSVersionTable.PSEdition)
        $dll = Join-Path $ScriptDir '.cache\winuse.dll'
        Write-Output ('kernel_dll=' + $(if (Test-Path $dll) { 'ok' } else { 'missing(首次运行自动编译)' }))
        $w = [WinUseNative]::ListWindows('', $true)
        Write-Output ('windows_enum=' + $w.Count)
        $fg = [WinUseNative]::ForegroundInfo()
        Write-Output ('foreground=' + $fg)
        if ($fg -match 'lock|logonui|screenlock|secure') {
            Write-Output '注意: 前台疑似锁屏/安全桌面，借焦点动作会被拒（后台 UIA/截图不受影响）'
        }
        Write-Output ('idle_ms=' + [WinUseNative]::IdleMilliseconds())
        $top = $w | Where-Object { $_.Visible -and $_.Rect.Width -gt 100 -and $_.Title } | Select-Object -First 1
        if ($top) {
            $scan = [WinUseNative]::UiScan($top.Hwnd, '', 5)
            $line0 = ($scan -split "`r?`n")[0].Trim()
            Write-Output ('uia_probe_window=' + $top.Owner + ' hwnd=0x' + $top.Hwnd.ToInt64().ToString('X'))
            Write-Output ('uia_probe=' + $(if ($line0 -like 'uia=on*') { $line0 } else { 'empty' }))
        } else {
            Write-Output 'uia_probe=无可用窗口'
        }
        Write-Output ('node(CDP需要)=' + $(if (Get-Command node -ErrorAction SilentlyContinue) { 'ok' } else { '缺失（只用 UIA/坐标时不需要）' }))
        if ([WinUseNative]::TryAcquireFocusLock()) {
            Write-Output 'focus_lock=空闲'
            [WinUseNative]::ReleaseFocusLock()
        } else {
            Write-Output 'focus_lock=被占用'
        }
        Write-Output 'doctor=done'
        break
    }

    default {
        $script:WIN_EXIT = 1
        Write-Output ('未知命令: ' + $cmd)
        Write-Output '可用: windows | fg | idle | open | shot | see | ax | axset | axpress | type | key | click | op | hud | doctor'
    }
}

exit $script:WIN_EXIT
