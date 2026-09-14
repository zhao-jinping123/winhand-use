# winhand-use 公开基准

这个目录回答三个问题，全部用可重跑的脚本和真实截图给证据：

1. **能控到什么层？** 同一个动作在沙箱里从 L1（UIA 语义）到 L3（后台截图）逐层验证。
2. **会不会打扰用户？** 每个场景记录动作前后的前台窗口，比较是否变化。
3. **动作真的生效了吗？** 不认工具返回值，只认读回、副作用文件和截图差分。

> 这不是跟其他框架比“谁更聪明”的排行榜。winhand-use 是给 Agent 用的“手”，
> 本基准测的是这双手在 Windows 上的可达能力、打扰程度和可验证性。

## 两层测试

### 1. 控制场景（可复现的沙箱 + 真实应用）

沙箱靶标在 `targets/`：

- `sandbox-form.exe`：两个可 UIA 写入的输入框 + 一个 UIA 按钮 + 一块纯自绘画布（无 UIA，只能走坐标层）。
- `cover-window.exe`：置顶遮挡层，用来验证“窗口被完全盖住时 PrintWindow 仍能截图”。
- `cdp-sandbox.html`：本地 Chromium 页面，配合无头 Edge 验证 L0 CDP 全链路（不碰用户正在用的浏览器）。

真实应用场景只读或用完即关，且在用户已有同名进程时自动跳过，避免干扰：

| 场景 | 层 | 断言 |
| --- | --- | --- |
| `sandbox.see` | L1 | 后台截图非黑；UIA 能看到两个输入框；前台窗口不变 |
| `sandbox.axset` | L1 | UIA 后台写入后读回一致；`effect=confirmed`；前台不变 |
| `sandbox.axpress` | L1 | UIA 触发按钮后副作用文件落盘且内容一致；前台不变 |
| `sandbox.occluded_shot` | L3 | 靶标被遮挡层完全盖住时截图仍非黑；截图前后前台不变 |
| `sandbox.op_dry` | L2 | `op --dry` 能给出预演结论；不产生副作用；前台不变 |
| `sandbox.cdp_flow` | L0 | 无头 Edge + 本地页面：`wait` → `text` 写值 → `click` → `eval` 读回 `state=saved` → `shot` 截图；前台不变 |
| `real.explorer_desktop` | L1/L3 | 桌面窗口可后台截图、UIA 可读 |
| `real.cdp_attach`（opt-in） | L0 | 本机 Edge 已开 CDP 时，只统计页面数量（`pages=N`），不读标题/URL/内容；依赖用户浏览器状态，默认不跑 |
| `real.calculator` | L1/L3 | 新实例最小化启动、无激活显示、后台截图成功、UIA 可读 |
| `real.mspaint` | L1/L3 | 同上（画图） |
| `real.notepad` | L0/L1 | 新实例测试；若用户已有记事本进程则跳过 |

### 2. 常用软件探测矩阵

对 12 个常见 Windows 应用跑 `probe.ps1`（只读：解析路径、版本、Chromium 判定、监听端口、CDP），
记录哪些能直接解析、哪些是 Chromium 系（可以优先走零焦点 CDP）。

当前列表：`notepad`、`calc`、`mspaint`、`explorer`、`msedge`、`chrome`、`Code`、
`Weixin`、`DingTalk`、`wps`、`JianyingPro`、`Doubao`。

## 运行

```powershell
# 完整基准（控制场景 + 真实应用 + 探测矩阵）
powershell -NoProfile -ExecutionPolicy Bypass -File benchmarks\run.ps1

# 只跑沙箱，不碰任何真实应用
powershell -NoProfile -ExecutionPolicy Bypass -File benchmarks\run.ps1 -SkipRealApps -SkipProbe

# 只跑常用软件探测矩阵
powershell -NoProfile -ExecutionPolicy Bypass -File benchmarks\run.ps1 -ProbeOnly

# 额外跑真实 Chromium 客户端 CDP 挂载（需要本机 Edge 已开调试端口）
powershell -NoProfile -ExecutionPolicy Bypass -File benchmarks\run.ps1 -IncludeCdpAttach

# 或者只跑这一个场景
powershell -NoProfile -ExecutionPolicy Bypass -File benchmarks\run.ps1 -Only real.cdp_attach -SkipProbe
```

结果写到 `benchmarks/results/<时间戳>/`：

- `report.json`：机器信息、技能提交、逐场景状态、耗时、证据文件、探测矩阵。
- `report.md`：给人看的表格版本。
- `shots/`：每个场景的原始截图（PNG，不压缩）。

## 结果怎么读

- `pass`：断言成立。
- `fail`：断言不成立，必须修。
- `skip`：不满足安全前提（例如用户已有同名应用进程），不算通过也不算失败。

关于“不打扰用户”的断言：UIA 读写与 CDP 场景检查的是**动作输出里没有借焦点/HUD 痕迹**
（即动作本身没有请求前台焦点）。动作前后前台窗口是否变化会作为参考数据记录，但不作为硬失败条件——
活桌面上用户自己的点击、输入法、通知弹窗都会改变前台窗口，直接比较会误判。

时间是参考值：当前每个 `win` 命令都会启动一个 Windows PowerShell 5.1 进程，
单次调用有 1-3 秒固定开销，所以沙箱场景的耗时主要来自进程启动，不代表操作本身的延迟。

结果绑定机器与应用版本：Windows 版本、DPI、应用版本一变，坐标类结论就要重测；
行为层结论（UIA 能不能用、CDP 端口、输入路径）相对耐用。样例会随仓库提交一份，
在 `results/sample/`。

`real.cdp_attach` 是 opt-in：它依赖“用户本机正好有一个开了 CDP 端口的 Chromium 应用”，
不放进默认样本；脚本只调用 `cdp.js count`，报告里只出现页面数量。

性能参考：常用软件探测矩阵最初串行执行 12 个 `probe.ps1` 要 573 秒；
改成每批 6 个受控并发后降到约 183–199 秒（同一台机器、同一组应用，视负载波动），结果不变。

## 加一个新应用

1. 先跑 `probe.cmd <应用名>`，把输出誊进 `references/app档案.md`。
2. 如果应用安全（不涉及账号、支付、隐私），在 `run.ps1` 里加一个 `real.<app>` 场景：
   最小化启动 → `win show` 无激活还原 → `win shot` / `win ax` → 关闭自己启动的进程。
3. 涉及用户账号、聊天记录、银行/医疗/政务的界面，只做只读探测，不加入控制场景。

## 已知边界

- `PrintWindow` 对最小化窗口会失败：先 `win show` 还原，或在应用原本可见时截。
- 跨虚拟桌面、锁屏、UAC 安全桌面下的写操作是硬墙，基准不会绕。
- 纯自绘画布没有 UIA 语义，只能走坐标层；本基准只验证 `--dry` 预演，不实际借焦点点击。
