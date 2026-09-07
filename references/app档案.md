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

## 待实测（装了就测，测完补）

剪映（JianyingPro）、豆包工作（DoubaoWork）、千问办公、微信（Weixin）、WPS、掘金量化终端（goldminer3）——重点记录：Chromium 系判定（进程树/WebView2）、CDP 端口是否可开、UIA editable、输入走哪条、回车语义、后台截图行不行。
