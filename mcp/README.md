# winhand-use MCP Server

零依赖 Node MCP Server：把 winhand-use 的 Windows 操控内核暴露成 MCP 工具，
任何支持 MCP 的 Agent 都能直接调用——不用把整份 SKILL.md 塞进上下文。

```text
Claude Code / Cursor / Codex / Claude Desktop
        │  MCP (stdio)
        ▼
   mcp/server.js  ──►  scripts/win.ps1 / probe.ps1 / cdp.js
```

## 工具

| 工具 | 类型 | 说明 |
| --- | --- | --- |
| `win_doctor` | 只读 | 环境自检 |
| `win_windows` / `win_fg` / `win_idle` | 只读 | 列窗口 / 前台窗口 / 空闲与焦点锁 |
| `win_show` | 非激活显示 | 显示或还原窗口但不抢焦点；可 `above` 做受控遮挡 |
| `win_see` / `win_shot` / `win_ax` | 只读 | 后台截图 / UIA 语义树 |
| `win_probe` | 只读 | 接手陌生 app 的第 0 步能力探测 |
| `win_axset` / `win_axpress` | 写 | UIA 后台写入 / 后台触发按钮 |
| `win_op` / `win_click` / `win_type` / `win_key` | 写 | 坐标与键盘输入，`win_op` 支持 `dry` 预演 |
| `win_open` | 写 | 启动应用，可带 CDP 调试端口 |
| `win_hud` | 界面提示 | 借焦点时屏幕四角取景框 |
| `win_cdp` | 写 | 对内嵌 Chromium 走 CDP：snapshot/find/mouse/insert/eval… |

写操作的工具都标了 `destructiveHint`，只读工具标了 `readOnlyHint`；具体停手线见仓库根目录 `SKILL.md`。

## 运行与自测

```powershell
# 启动（一般由 MCP 客户端拉起，不需要手动跑）
node mcp\server.js

# 自测：initialize → tools/list → tools/call(win_doctor)
node mcp\selftest.js
```

环境变量：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `WINHAND_MCP_PS` | `powershell.exe` | 必须用 Windows PowerShell 5.1，不要换成 pwsh |
| `WINHAND_MCP_TIMEOUT_MS` | `120000` | 单个工具调用超时 |
| `WINHAND_MCP_MAX_OUTPUT` | `20000` | 返回文本上限（超出截断），避免灌爆上下文 |

## 配置示例

### Codex（`~/.codex/config.toml`）

```toml
[mcp_servers.winhand]
command = "node"
args = ["C:/Users/<你>/.codex/skills/winhand-use/mcp/server.js"]
startup_timeout_sec = 60
```

### Claude Code / Cursor（项目根 `.mcp.json`）

```json
{
  "mcpServers": {
    "winhand": {
      "command": "node",
      "args": ["C:/Users/<你>/.codex/skills/winhand-use/mcp/server.js"]
    }
  }
}
```

### Claude Desktop（`claude_desktop_config.json`）

```json
{
  "mcpServers": {
    "winhand": {
      "command": "node",
      "args": ["C:/Users/<你>/.codex/skills/winhand-use/mcp/server.js"]
    }
  }
}
```

## 安全

MCP 工具以你的用户权限运行，能读写窗口、截图和发送输入。建议：

1. Agent 先调用 `win_doctor` 和 `win_probe`，再决定用哪一层。
2. 写操作前先 `win_op` 的 `dry=true` 预演；不可逆动作交还用户。
3. 银行/券商/医疗/政务、聊天记录与账号界面不接入自动化。
4. 只读工具可以放心给 Agent；写工具在客户端侧按需开启人工确认。
