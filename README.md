<div align="center">

# winhand-use · Windows Computer-Use Agent Skill

**给任何 coding agent 一双在 Windows 上操作的手**：操控没有 API 的 Windows 原生 App，并把每一步留成可复现的取证。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-blue)](#前置条件)
[![Runtime](https://img.shields.io/badge/Runtime-Claude%20Code%20%C2%B7%20Codex%20%C2%B7%20Cursor%20%C2%B7%20Kimi%20Code%20%C2%B7%20OpenClaw-violet)](#安装)

> **架构来源**：本项目是 [huashu-mac-use](https://github.com/alchaincyf/huashu-mac-use)（[花叔](https://x.com/AlchainHust)，MIT）的 **Windows 重写版**——
> 沿用原版「四层控制面、读写分离、动作回读取证」的整套架构与心智，把 macOS 内核（Swift + Accessibility）换成 Windows 原生技术栈（Win32 + UIA + PowerShell），`cdp.js` 原样复用。向原作者的优秀设计致谢。

</div>

## 它解决什么问题

白领任务的最后一步大多发生在桌面 App 里，而这些 App 常常既没有 API 也没有命令行。这个技能让 agent（Claude Code / Codex / Cursor / Kimi Code / ZCode / Hermes / DeepSeek harness……）按原版三条原则工作：

1. **先探测，再选层**：四层控制面，越往上越省事越稳——L0 结构接口（自带 CLI/COM、CDP、本地端口、URL scheme）→ L1 UIA 语义树（后台读写）→ L2 窗口坐标 → L3 像素截图。
2. **读完全后台，写默认零焦点**：窗口被遮挡也能后台截图（PrintWindow）；UIA 直写、UIA Invoke 触发按钮都不碰焦点；判不出生效才借焦点，且要过四道闸（前台/遮挡/在场/全机焦点锁），借到的那半秒屏幕四角闪橙色取景框。
3. **工具说成功不算数**：动作后自动截图差分 + 读回，回 `effect=confirmed|partial|suspected_noop|unverifiable`；`suspected_noop` 不是失败，是「回去重看」。

## 实测记录（2026-09-07，Windows 11）

- 后台窗口截图（被遮挡可截、DPI 物理像素一致）
- UIA 读树 / 后台写入 + 读回一致（含中文无损）
- 端到端沙盒操控：双输入框窗口精确写入指定框 → UIA 触发按钮 → 副作用文件落盘，全程零焦点
- 退出码三态（0/1/2）供 agent 框架判断

## 前置条件

- Windows 10/11
- Windows PowerShell 5.1（系统自带；**不要用 pwsh**，UIA 依赖 .NET Framework）
- Node.js（仅内嵌 Chromium 的 App 走 CDP 时需要）

## 安装

把仓库克隆或复制到目标 runtime 的 skills 目录：

| Runtime | 目录 |
|---|---|
| Codex | `~/.codex/skills/winhand-use` |
| Claude Code | `~/.claude/skills/winhand-use` |
| Cursor | `~/.cursor/skills/winhand-use` |
| 其它 | 见 `references/多框架适配.md` |

```powershell
git clone https://github.com/zhao-jinping123/winhand-use.git ~/.codex/skills/winhand-use
# 任何 runtime：首次使用先自检
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\.codex\skills\winhand-use\scripts\win.ps1" doctor
```

首次运行自动编译 C# 内核到 `scripts\.cache\`，无需手动 build。

## 快速上手

```powershell
# 环境自检（换框架/新机器第一步）
winhand doctor

# 探测某个 app 能不能自动化
probe.cmd 记事本

# 列窗口 / 后台截窗口（不打扰用户）
winhand windows
winhand shot <目标> 输出.png

# 看界面 + UIA 元素表 → 后台写文本 → 后台触发按钮
winhand see <目标>
winhand axset <目标> e0 "文本"
winhand axpress <目标> e1

# 坐标点击输入（自动后台→借焦点阶梯；先 --dry 预演）
winhand op <目标> 100 200 "文本" @截图.png --dry
```

完整命令表、四层控制面详解、停手线、取证回流规则见 `SKILL.md` 与 `references/`。

## 停手线（摘要）

发布/付款/删除/覆盖保存等不可逆动作、终端回车、UAC 弹窗、银行/券商/医疗/政务界面——一律交还用户，不绕。

## 目录结构

```text
winhand-use/
├── SKILL.md                 # 身份、四层控制面、命令表、停手线、回流规则
├── scripts/
│   ├── win.ps1              # Windows 操控内核（PowerShell + C#：窗口/截图/UIA/事件/四道闸/HUD）
│   ├── winuse.cs.inc        # Win32/UIA 辅助层（自动编译）
│   ├── win.cmd / probe.cmd  # 命令入口
│   ├── probe.ps1            # 第 0 步能力探测
│   └── cdp.js               # 内嵌 Chromium 的 CDP 工具（复用 huashu-mac-use）
└── references/
    ├── 控制面详解.md / 权限与故障.md / app档案.md
    ├── 取证规范.md / 踩坑实录.md / 多框架适配.md
```

## 许可

MIT。基于 [huashu-mac-use](https://github.com/alchaincyf/huashu-mac-use)（MIT，Copyright (c) 2026 花叔）改写；`cdp.js` 原样复用。详见 [LICENSE](LICENSE)。
