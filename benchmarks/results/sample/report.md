# winhand-use benchmark report

- 时间：2026-09-14T11:33:46.8615756+08:00
- 机器：Microsoft Windows 11 家庭版 中文版 10.0.26200 / PowerShell 5.1.26100.9444
- 技能提交：25585e1
- 汇总：10 pass / 0 fail / 1 skip，总耗时 1345098 ms

| 场景 | 层 | 结果 | 耗时(ms) | 说明 |
| --- | --- | --- | --- | --- |
| sandbox.see | L1 | pass | 137254 | 截图=True black=0.553 editable=2 UIA含双输入框=True 前台未变=True |
| sandbox.axset | L1 | pass | 227573 | selector=e1 写回一致=True effect=confirmed=True 未借焦点=True 前台未变=True 用户活动=False idle_before=1674200ms idle_after=1770000ms |
| sandbox.axpress | L1 | pass | 223416 | button=e2 副作用落盘=True 内容一致=True 未借焦点=True 前台未变=True 用户活动=False idle_before=1958300ms idle_after=1993600ms |
| sandbox.occluded_shot | L3 | pass | 152581 | 遮挡下截图=True size=1118x694 black=0.553 bytes=31127 截图前后前台未变=True |
| sandbox.op_dry | L2 | pass | 61557 | dry预演可见=True 未执行副作用=True 前台未变=True exit=0 |
| sandbox.cdp_flow | L0 | pass | 21307 | CDP端口=9339 wait=True 写值+点击+读回=True 截图=True 前台未变=True |
| real.explorer_desktop | L1/L3 | pass | 43859 | 桌面截图=True black=0.005 UIA可读=True |
| real.notepad | L0/L1 | skip | 46 | 用户已有记事本进程，跳过以避免干扰 |
| real.calculator | L1/L3 | pass | 92357 | 后台截图=True black=0.011 UIA元素=62 |
| real.mspaint | L1/L3 | pass | 183851 | 后台截图=True black=0.001 UIA元素=101 |
| probe.matrix | L0/L1 | pass | 198727 | 探测 11/12 可解析，探针错误=0，Chromium=5 CDP=1 |

## 常用软件探测矩阵

| 应用 | 可解析 | 版本 | Chromium | CDP | 备注 |
| --- | --- | --- | --- | --- | --- |
| notepad | True | 11.2607.14.0 | False | False |  |
| calc | True | 10.0.26100.8521 (WinBuild.160101.0800) | False | False |  |
| mspaint | True | 11.2605.81.0 | False | False |  |
| explorer | True | 10.0.26100.8875 (WinBuild.160101.0800) | False | False |  |
| msedge | True | 153.0.4234.32 | True | True |  |
| chrome | True | 128.1.6541.23 | True | False |  |
| Code | True |  | False | False |  |
| Weixin | True | 4.1.13.65 | True | False |  |
| DingTalk | True | 8.1.5.251107001 | True | False |  |
| wps | True | 12,1,0,28505 | False | False |  |
| JianyingPro | False |  | False | False | 未找到应用 |
| Doubao | True | 147.0.7727.149 | True | False |  |
