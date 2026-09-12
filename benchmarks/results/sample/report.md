# winhand-use benchmark report

- 时间：2026-09-13T00:19:42.0048896+08:00
- 机器：Microsoft Windows 11 家庭版 中文版 10.0.26200 / PowerShell 5.1.26100.9444
- 技能提交：8970c7e
- 汇总：9 pass / 0 fail / 1 skip，总耗时 440407 ms

| 场景 | 层 | 结果 | 耗时(ms) | 说明 |
| --- | --- | --- | --- | --- |
| sandbox.see | L1 | pass | 28073 | 截图=True black=0.553 editable=2 UIA含双输入框=True 前台未变=True |
| sandbox.axset | L1 | pass | 44283 | selector=e1 写回一致=True effect=confirmed=True 前台未变=True |
| sandbox.axpress | L1 | pass | 55454 | button=e2 副作用落盘=True 内容一致=True 前台未变=True |
| sandbox.occluded_shot | L3 | pass | 48808 | 遮挡下截图=True black=0.553 截图前后前台未变=True |
| sandbox.op_dry | L2 | pass | 26003 | dry预演可见=True 未执行副作用=True 前台未变=True exit=0 |
| real.explorer_desktop | L1/L3 | pass | 15993 | 桌面截图=True black=0.005 UIA可读=True |
| real.notepad | L0/L1 | skip | 17 | 用户已有记事本进程，跳过以避免干扰 |
| real.calculator | L1/L3 | pass | 32024 | 后台截图=True black=0.011 UIA元素=62 |
| real.mspaint | L1/L3 | pass | 36777 | 后台截图=True black=0.001 UIA元素=101 |
| probe.matrix | L0/L1 | pass | 152325 | 探测 11/12 可解析，探针错误=0，Chromium=5 CDP=1 |

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
