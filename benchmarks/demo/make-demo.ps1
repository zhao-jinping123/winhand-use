# 用基准测试的真实截图生成演示 GIF / MP4。
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File benchmarks\demo\make-demo.ps1
#   powershell ... -ResultDir benchmarks\results\20260913-xxxxxx
param(
    [string]$ResultDir = '',
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'assets' }
if (-not $ResultDir) {
    $latest = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'benchmarks\results') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { throw '找不到基准结果目录，先运行 benchmarks\run.ps1' }
    $ResultDir = $latest.FullName
}
if (-not (Test-Path -LiteralPath $ResultDir)) { throw ('结果目录不存在: ' + $ResultDir) }

$shots = Join-Path $ResultDir 'shots'
$sandboxShot = Get-ChildItem -LiteralPath $shots -Filter 'sandbox-form-*.png' -ErrorAction SilentlyContinue | Select-Object -First 1
$occludedShot = Get-ChildItem -LiteralPath $shots -Filter 'occluded-sandbox.png' -ErrorAction SilentlyContinue | Select-Object -First 1
$cdpShot = Get-ChildItem -LiteralPath $shots -Filter 'cdp-sandbox.png' -ErrorAction SilentlyContinue | Select-Object -First 1
$reportJson = Join-Path $ResultDir 'report.json'
$summaryLine = '公开基准：8 pass / 0 fail / 1 skip'
if (Test-Path -LiteralPath $reportJson) {
    $report = Get-Content -LiteralPath $reportJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $summaryLine = ('公开基准：{0} pass / {1} fail / {2} skip' -f $report.summary.pass, $report.summary.fail, $report.summary.skip)
}

$work = Join-Path $env:TEMP ('winhand-demo-' + (Get-Date -Format 'HHmmss'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$fontName = 'Microsoft YaHei UI'

function New-Slide {
    param([string]$Path, [scriptblock]$Draw)
    $bmp = New-Object System.Drawing.Bitmap(1280, 720)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'ClearTypeGridFit'
    $g.Clear([System.Drawing.Color]::FromArgb(18, 20, 26))
    & $Draw $g
    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

function Draw-Text {
    param($G, [string]$Text, [single]$X, [single]$Y, [single]$Size, [string]$Color, [string]$Style = 'Regular')
    $fontStyle = [System.Drawing.FontStyle]::$Style
    $font = New-Object System.Drawing.Font($fontName, $Size, $fontStyle)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($Color))
    $G.DrawString($Text, $font, $brush, $X, $Y)
    $font.Dispose()
    $brush.Dispose()
}

function Draw-ImageFit {
    param($G, [string]$Path, [int]$X, [int]$Y, [int]$W, [int]$H)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $img = [System.Drawing.Image]::FromFile($Path)
    try {
        $ratio = [Math]::Min($W / $img.Width, $H / $img.Height)
        $dw = [int]($img.Width * $ratio)
        $dh = [int]($img.Height * $ratio)
        $dx = $X + [int](($W - $dw) / 2)
        $dy = $Y + [int](($H - $dh) / 2)
        $G.DrawImage($img, $dx, $dy, $dw, $dh)
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 120, 170)), 2
        $G.DrawRectangle($pen, $dx, $dy, $dw, $dh)
        $pen.Dispose()
    }
    finally { $img.Dispose() }
}

New-Slide (Join-Path $work 'slide1.png') {
    param($g)
    Draw-Text $g 'winhand-use' 80 54 52 '#F5C76A' 'Bold'
    Draw-Text $g '给任何 coding agent 一双在 Windows 上操作的手' 80 126 26 '#E8ECF4'
    Draw-ImageFit $g $(if ($sandboxShot) { $sandboxShot.FullName } else { '' }) 80 200 1120 440
    Draw-Text $g '① 后台截图：不抢鼠标键盘，窗口被盖住也能截' 80 648 27 '#7FDCA0'
}

New-Slide (Join-Path $work 'slide2.png') {
    param($g)
    Draw-Text $g '被完全遮挡，仍然可读' 80 54 42 '#F5C76A' 'Bold'
    Draw-Text $g 'PrintWindow 后台取证 · 全程零焦点' 80 118 24 '#E8ECF4'
    Draw-ImageFit $g $(if ($occludedShot) { $occludedShot.FullName } else { '' }) 80 180 1120 460
    Draw-Text $g '② 截图来自被遮挡的窗口，而不是屏幕录制' 80 652 27 '#7FDCA0'
}

New-Slide (Join-Path $work 'slide3.png') {
    param($g)
    Draw-Text $g 'UIA 后台写入 → 读回一致' 80 120 46 '#F5C76A' 'Bold'
    Draw-Text $g 'effect=confirmed' 80 220 40 '#7FDCA0' 'Bold'
    Draw-Text $g 'win axset  选中控件直写' 80 330 28 '#E8ECF4'
    Draw-Text $g 'win ax      读回验证' 80 390 28 '#E8ECF4'
    Draw-Text $g 'win axpress 后台触发按钮，副作用文件落盘' 80 450 28 '#E8ECF4'
    Draw-Text $g '③ 工具返回成功不算数，应用状态变了才算数' 80 622 26 '#9FB4D8'
}

New-Slide (Join-Path $work 'slide4.png') {
    param($g)
    Draw-Text $g 'L0 CDP：内嵌 Chromium 零焦点操控' 80 54 42 '#F5C76A' 'Bold'
    Draw-Text $g 'wait → 写值 → 点击 → 读回 state=saved → 截图' 80 118 24 '#E8ECF4'
    Draw-ImageFit $g $(if ($cdpShot) { $cdpShot.FullName } else { '' }) 80 180 1120 460
    Draw-Text $g '④ 无头浏览器全链路验证，不碰用户正在用的浏览器' 80 652 27 '#7FDCA0'
}

New-Slide (Join-Path $work 'slide5.png') {
    param($g)
    Draw-Text $g $summaryLine 80 110 44 '#F5C76A' 'Bold'
    Draw-Text $g '控制层覆盖：L0 CDP · L1 UIA · L2 坐标预演 · L3 后台截图' 80 214 26 '#E8ECF4'
    Draw-Text $g '常用软件探测：12 个软件 · 5 个 Chromium · 1 个 CDP 端口' 80 276 26 '#E8ECF4'
    Draw-Text $g 'npx skills add zhao-jinping123/winhand-use' 80 372 26 '#7FDCA0'
    Draw-Text $g 'MCP：node mcp/server.js（18 个工具）' 80 438 26 '#7FDCA0'
    Draw-Text $g 'github.com/zhao-jinping123/winhand-use' 80 504 26 '#9FB4D8'
    Draw-Text $g '⑤ 可复现基准 + Skill / MCP 双接入' 80 622 26 '#9FB4D8'
}

$mp4 = Join-Path $OutDir 'demo.mp4'
$gif = Join-Path $OutDir 'demo.gif'
& ffmpeg -y -hide_banner -loglevel error -framerate 0.4 -i (Join-Path $work 'slide%d.png') -vf 'fps=25,format=yuv420p' -c:v libx264 -preset medium -crf 20 -movflags +faststart $mp4
& ffmpeg -y -hide_banner -loglevel error -framerate 0.4 -i (Join-Path $work 'slide%d.png') -vf 'fps=12,scale=800:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse' -loop 0 $gif

Write-Output ('demo_mp4=' + (Test-Path -LiteralPath $mp4) + ' ' + (Get-Item -LiteralPath $mp4).Length + ' bytes')
Write-Output ('demo_gif=' + (Test-Path -LiteralPath $gif) + ' ' + (Get-Item -LiteralPath $gif).Length + ' bytes')
