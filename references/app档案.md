# per-app 操控档案（Windows）

> 🔴 **易腐声明。** 坐标、窗口尺寸、按钮位置、菜单层级、端口号、界面文案全部是易腐信息，产品一改版就废。
>
> **坐标不是用来点的，是用来事后对照的。** 动手一律先 `win see` 截现场、按锚点描述在图上找到控件、量坐标再点（流程见 SKILL.md）。点完了才回来看档案：**点中说明档案仍有效；点空说明已改版，立刻改档案。**
>
> **绝不要把这里的坐标当结论写进别的地方。** 真正耐用的是「行为」几行：架构、UIA 能不能用、有没有本地端口、回车是不是发送、输入走哪条路。

## 怎么维护

1. 每个易腐字段行尾带 `# 核对 YYYY-MM-DD`，没日期的按「未核对」。
2. **核对第一步是比版本号**（exe 的 FileVersion）。🔴 版本变了，本条坐标一律作废，行为层（UIA/端口/回车语义）全部重测。
3. 坐标对不上就地改那一行并更新日期，不新增条目（同一个 app 永远一条记录）。
4. **怎么增补新 app**：跑 `probe.cmd <应用名>`，把输出誊成下面的 yaml 骨架；probe 探不到的「输入/发送/借焦点/坑」四行实测后补。全部写实测日期。

坐标怎么记：归一化坐标（4 位小数）+ 锚点描述 + 实测窗口尺寸。核对判据：量出的归一化坐标与档案差 >0.02 就改。

```yaml
exe: <进程名>
版本: <FileVersion>              # 核对 YYYY-MM-DD
显示名/窗口标题特征: <…>           # win windows 用
架构: 原生 Win32 / WinUI3 / Electron / CEF / WebView2 / Qt / Java / 自绘
L0: ❌/✅ 说明（CLI/COM/本地端口/CDP/URL scheme）
L1 UIA: ✅ 可编辑控件 path=… / ❌ 树空 / ⚠️ 暗拒（字进得去状态不更新）
输入: UIA ValuePattern / SendInput Unicode / 剪贴板 / 只认真实按键
发送: 回车=发送？还是换行？（实测，别猜）
后台截图: ✅ PrintWindow 直接可截 / ⚠️ 黑屏要 --fg / ❌ 截不到
借焦点: 顺 / 难（前台锁/安全软件）
坑: <单条实测，能变成工具行为的直接改代码>
```

---

## 记事本（Windows 11 新版，WinUI3）· 实测 2026-09-07

```yaml
exe: Notepad
版本: 11.2402+                  # 核对 2026-09-07
架构: WinUI3（多窗口单进程：新标签/新窗口都开在同一 pid）
  ⚠️ notepad.exe 启动器是 stub：Start-Process notepad 可能复用旧实例，
  新窗口属于旧 pid；拿 pid 反查会先撞上 IME/隐藏小窗（主窗口启发式已处理）
L0: ❌ 无 CDP/CLI 操控；open file 参数可用（notepad <path> 开文件）
L1 UIA: ✅ 文本区是 Document path=0/0（根 children[0]=Pane → children[0]=Document）
  ⚠️ Document 的 ValuePattern IsReadOnly=true → axset 报 fail:readonly！
  实测写入走不了 SetValue（新版记事本只读）。要写内容：用 op 借焦点真实键入，
  或直接以 CLI 打开文件让 app 加载（编辑文件本体走文件 API，别打 UI）
输入: 只认真实键盘（SendInput Unicode 有效）
发送: 无发送键概念；Ctrl+S 保存
后台截图: ✅ PrintWindow 直接可截（还原态，即使被遮挡）；❌ 最小化截不到
借焦点: 顺（普通进程）
坑: Document 只读是「真只读」不是暗拒——axset 会明确报 readonly，别绕
```

实测备忘（2026-09-07）：写测试文本到新标签时用的不是 UIA，而是**预先把文件内容写好再打开**（等价 L0：改文件让 app 加载），这符合「能不点就不点」原则；关闭窗口用 WM_CLOSE，内容未变时不弹保存框。

---

## 资源管理器桌面（Program Manager / WorkerW）· 实测 2026-09-07

```yaml
exe: explorer
架构: 原生 shell
L1 UIA: ✅ 桌面 List（path=2，aid=1）下有 ListItem=桌面图标；47 个可编辑控件其实是
  每个图标的 value（桌面图标在 UIA 里被报成可编辑？实测如此，别信 editable 数字）
后台截图: ✅ PrintWindow 对桌面窗口可截 1920×1080（物理像素）
坑: 桌面 hwnd=Program Manager 是 shell 窗口；截图可直接当「当前屏幕状态」取证，
  但它不含任务栏和别的窗口。桌面图标坐标从图量即可
```

---

## 计算器（Windows 11，UWP / WinUI3）· 实测 2026-09-13

```yaml
exe: calc.exe（System32 stub，实际进程 CalculatorApp）
版本: 10.0.26100.8521            # 核对 2026-09-13
显示名/窗口标题特征: 计算器 / Calculator
架构: UWP / WinUI3
L0: ❌ 无 CLI/本地端口；shell:AppsFolder 可启动
L1 UIA: ✅ 基准实测 elements=62（数字键/运算符都可读）
输入: UIA Invoke 触发按钮；坐标层可用（控件规整）
后台截图: ✅ PrintWindow 直接可截（black=0.011）
借焦点: 用 win show 无激活还原；测试结束按 CalculatorApp/Calculator/calc 关闭自己启动的实例
坑: probe 需要「系统目录同名 exe」回退才能解析 calc.exe；用户已有计算器时基准自动跳过
```

## 画图（Windows 11，WinUI3）· 实测 2026-09-13

```yaml
exe: mspaint.exe
版本: 11.2605.81.0               # 核对 2026-09-13
架构: WinUI3
L0: ❌ 无 CLI/端口；文件参数可打开图片
L1 UIA: ✅ 基准实测 elements=101（工具栏/画布容器可读）
后台截图: ✅ PrintWindow 直接可截（black=0.001）
借焦点: 用 win show 无激活还原；用户已有画图时基准自动跳过
坑: 纯画布内容没有 UIA 语义，画图内容本身要走坐标/像素层验证
```

---

## 首轮公开探测矩阵（2026-09-13，只读）

> 由 `benchmarks/run.ps1 -ProbeOnly` 采集。只代表「静态路径 + L0 结构接口」，
> UIA 与输入路径要等应用运行后另测。`JianyingPro` 本机未安装。

| 应用 | 版本 | Chromium 系 | 已开 CDP | 结论 |
| --- | --- | --- | --- | --- |
| notepad | 11.2607.14.0 | ❌ | ❌ | 走 UIA/文件加载；文档区只读 |
| calc | 10.0.26100.8521 | ❌ | ❌ | UIA 元素齐全，可后台 Invoke |
| mspaint | 11.2605.81.0 | ❌ | ❌ | UIA 读工具栏；画布内容走坐标层 |
| explorer | 10.0.26100.8875 | ❌ | ❌ | 桌面截图 + UIA 读图标列表 |
| msedge | 153.0.4234.32 | ✅ | ✅ | 优先走 CDP（测试时端口 9382） |
| chrome | 128.1.6541.23 | ✅ | ❌ | 可优先试 CDP；未开调试端口时走 UIA/坐标 |
| Code | （版本待补） | ❌ | ❌ | Electron 系，按 Chromium 处理，优先 CDP |
| Weixin | 4.1.13.65 | ✅ | ❌ | Chromium 系，优先 CDP；聊天内容属隐私，只读探测 |
| DingTalk | 8.1.5.251107001 | ✅ | ❌ | Chromium 系，优先 CDP |
| wps | 12,1,0,28505 | ❌ | ❌ | 原生系，走 UIA/坐标 |
| Doubao | 147.0.7727.149 | ✅ | ❌ | Chromium 系，优先 CDP |
| JianyingPro | — | — | — | 本机未找到，待安装后补测 |

## 待实测（运行后补输入/发送/借焦点四行）

Weixin、DingTalk、WPS、Doubao、Code —— 重点记录：CDP 端口能否由我们来开、
UIA editable 数量、输入走 UIA / SendInput / 剪贴板哪条、回车语义、后台截图行不行。
聊天与账号类界面只做只读探测，不加入自动化控制场景。
