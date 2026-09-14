#!/usr/bin/env node
// winhand-use MCP Server：把 Windows 操控内核暴露成 MCP 工具。
// 零依赖：只用 Node 内置模块 + 本仓库的 PowerShell 脚本。
// stdout 只输出 JSON-RPC 协议消息，日志一律走 stderr。
'use strict';

const { spawn } = require('child_process');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const WIN_PS1 = path.join(ROOT, 'scripts', 'win.ps1');
const PROBE_PS1 = path.join(ROOT, 'scripts', 'probe.ps1');
const CDP_JS = path.join(ROOT, 'scripts', 'cdp.js');
const POWERSHELL = process.env.WINHAND_MCP_PS || 'powershell.exe';
const TIMEOUT_MS = Number(process.env.WINHAND_MCP_TIMEOUT_MS || 120000);
const MAX_OUTPUT = Number(process.env.WINHAND_MCP_MAX_OUTPUT || 20000);
const SERVER_VERSION = '1.0.0';

const SUPPORTED_PROTOCOLS = ['2024-11-05', '2025-03-26', '2025-06-18'];
const DEFAULT_PROTOCOL = '2024-11-05';

// ───────────────────────── 工具定义 ─────────────────────────

const TOOLS = [
    {
        name: 'win_doctor',
        description: '环境自检：Windows/PS 版本、内核编译、窗口枚举、UIA 探针、锁屏与焦点锁。换机器或怀疑环境问题时先跑。',
        readOnly: true,
        inputSchema: { type: 'object', properties: {}, additionalProperties: false },
        build: () => ['doctor'],
    },
    {
        name: 'win_windows',
        description: '列出窗口：hwnd / pid / owner / 是否当前桌面 / 最小化 / 尺寸 / 标题。关键词按 owner 或标题模糊匹配。',
        readOnly: true,
        inputSchema: {
            type: 'object',
            properties: {
                keyword: { type: 'string', description: 'owner 或标题关键词，可省略' },
                all: { type: 'boolean', description: '包含隐藏窗口，默认 false' },
            },
            additionalProperties: false,
        },
        build: (a) => ['windows', ...(a.keyword ? [a.keyword] : []), ...(a.all ? ['--all'] : [])],
    },
    {
        name: 'win_fg',
        description: '当前前台窗口 + 键鼠空闲毫秒。动手前用它判断用户是否正在用电脑。',
        readOnly: true,
        inputSchema: { type: 'object', properties: {}, additionalProperties: false },
        build: () => ['fg'],
    },
    {
        name: 'win_idle',
        description: '键鼠空闲秒数 + 前台窗口 + 焦点锁状态。借焦点写操作前的前置检查。',
        readOnly: true,
        inputSchema: { type: 'object', properties: {}, additionalProperties: false },
        build: () => ['idle'],
    },
    {
        name: 'win_show',
        description: '显示/还原窗口但不抢焦点；above 指定时把窗口压到参照窗口正上方（受控遮挡取证）。',
        inputSchema: {
            type: 'object',
            properties: {
                target: { type: 'string', description: 'hwnd(0x..) / pid / owner 或标题关键词 / fg' },
                above: { type: 'string', description: '可选：参照窗口，放在它正上方' },
            },
            required: ['target'],
            additionalProperties: false,
        },
        build: (a) => ['show', a.target, ...(a.above ? ['--above', a.above] : [])],
    },
    {
        name: 'win_see',
        description: '一次拿到窗口收据 + 后台截图 + UIA 可交互元素表（e0/e1…）。首选侦察命令，读操作不打扰用户。',
        readOnly: true,
        inputSchema: {
            type: 'object',
            properties: {
                target: { type: 'string' },
                out_dir: { type: 'string', description: '截图输出目录，省略则写临时目录' },
            },
            required: ['target'],
            additionalProperties: false,
        },
        build: (a) => ['see', a.target, ...(a.out_dir ? ['--out', a.out_dir] : [])],
    },
    {
        name: 'win_shot',
        description: '后台截窗口（被遮挡也能截）；fg=true 才借焦点前台截图。最小化窗口会失败，先 win_show。',
        readOnly: true,
        inputSchema: {
            type: 'object',
            properties: {
                target: { type: 'string' },
                out: { type: 'string', description: '输出 PNG 绝对路径' },
                fg: { type: 'boolean', description: '是否允许借焦点前台截图，默认 false' },
            },
            required: ['target', 'out'],
            additionalProperties: false,
        },
        build: (a) => ['shot', a.target, a.out, ...(a.fg ? ['--fg'] : [])],
    },
    {
        name: 'win_ax',
        description: '读取 UIA 语义树摘要（editable/clickable + e0/e1 元素路径）。可用 keyword 过滤。',
        readOnly: true,
        inputSchema: {
            type: 'object',
            properties: {
                target: { type: 'string' },
                keyword: { type: 'string', description: '元素名/类型关键词，可省略' },
            },
            required: ['target'],
            additionalProperties: false,
        },
        build: (a) => ['ax', a.target, ...(a.keyword ? [a.keyword] : [])],
    },
    {
        name: 'win_axset',
        description: 'UIA 后台写入控件并读回（零焦点首选）。写操作：会覆盖控件原内容，先 win_ax 读一遍。',
        destructive: true,
        inputSchema: {
            type: 'object',
            properties: {
                target: { type: 'string' },
                selector: { type: 'string', description: 'e0 / path / 关键词' },
                text: { type: 'string' },
            },
            required: ['target', 'selector', 'text'],
            additionalProperties: false,
        },
        build: (a) => ['axset', a.target, a.selector, a.text],
    },
    {
        name: 'win_axpress',
        description: 'UIA Invoke 后台触发按钮/菜单（零焦点）。可能触发不可逆动作，调用前确认停手线；触发后必须用截图或副作用验证。',
        destructive: true,
        inputSchema: {
            type: 'object',
            properties: {
                target: { type: 'string' },
                selector: { type: 'string', description: 'e0 / path / 关键词' },
            },
            required: ['target', 'selector'],
            additionalProperties: false,
        },
        build: (a) => ['axpress', a.target, a.selector],
    },
    {
        name: 'win_op',
        description: '写操作默认入口：后台 PostClick + 落点 UIA 直写 → 截图差分 → 判不出才借焦点。先 dry=true 预演。',
        destructive: true,
        inputSchema: {
            type: 'object',
            properties: {
                target: { type: 'string' },
                x: { type: 'number' },
                y: { type: 'number' },
                text: { type: 'string', description: '写入文本，可为空' },
                image: { type: 'string', description: '坐标参考截图 x,y@图.png，可省略' },
                dry: { type: 'boolean', description: '只预演不执行，默认 false' },
                bg: { type: 'boolean', description: '强制后台档' },
            },
            required: ['target', 'x', 'y'],
            additionalProperties: false,
        },
        build: (a) => [
            'op', a.target, String(a.x), String(a.y), a.text || '',
            ...(a.image ? [a.image] : []),
            ...(a.dry ? ['--dry'] : []),
            ...(a.bg ? ['--bg'] : []),
        ],
    },
    {
        name: 'win_click',
        description: '只点击不输入：win_op 的无文本版，支持 dry 预演。',
        destructive: true,
        inputSchema: {
            type: 'object',
            properties: {
                target: { type: 'string' },
                x: { type: 'number' },
                y: { type: 'number' },
                image: { type: 'string' },
                dry: { type: 'boolean' },
            },
            required: ['target', 'x', 'y'],
            additionalProperties: false,
        },
        build: (a) => [
            'click', a.target, String(a.x), String(a.y),
            ...(a.image ? [a.image] : []),
            ...(a.dry ? ['--dry'] : []),
        ],
    },
    {
        name: 'win_type',
        description: '输入文本（默认全局 SendInput Unicode，要求目标在前台；bg=true 走 UIA 后台写）。',
        destructive: true,
        inputSchema: {
            type: 'object',
            properties: {
                target: { type: 'string' },
                text: { type: 'string' },
                bg: { type: 'boolean' },
            },
            required: ['target', 'text'],
            additionalProperties: false,
        },
        build: (a) => ['type', a.target, a.text, ...(a.bg ? ['--bg'] : [])],
    },
    {
        name: 'win_key',
        description: '发送按键或组合键（Enter/Esc/Tab/F5/ctrl+c…）。回车可能是不可逆动作，先确认。',
        destructive: true,
        inputSchema: {
            type: 'object',
            properties: {
                target: { type: 'string' },
                key: { type: 'string' },
                bg: { type: 'boolean' },
            },
            required: ['target', 'key'],
            additionalProperties: false,
        },
        build: (a) => ['key', a.target, a.key, ...(a.bg ? ['--bg'] : [])],
    },
    {
        name: 'win_open',
        description: '启动应用（中文显示名/exe/开始菜单名解析）；cdp 指定调试端口并等到通；relaunch 会先关当前实例（有丢数据风险）。',
        destructive: true,
        inputSchema: {
            type: 'object',
            properties: {
                name: { type: 'string' },
                cdp: { type: 'number', description: '可选：带 --remote-debugging-port 启动并等待 CDP 就绪' },
                relaunch: { type: 'boolean', description: '先关闭正在运行的实例，默认 false' },
            },
            required: ['name'],
            additionalProperties: false,
        },
        build: (a) => ['open', a.name, ...(a.cdp ? ['--cdp', String(a.cdp)] : []), ...(a.relaunch ? ['--relaunch'] : [])],
    },
    {
        name: 'win_hud',
        description: '屏幕四角橙色取景框（借焦点时自动闪，一般不用手调）。',
        inputSchema: {
            type: 'object',
            properties: {
                ms: { type: 'number', description: '显示毫秒数' },
                text: { type: 'string', description: '可选文案' },
            },
            required: ['ms'],
            additionalProperties: false,
        },
        build: (a) => ['hud', String(a.ms), ...(a.text ? [a.text] : [])],
    },
    {
        name: 'win_probe',
        description: '第 0 步能力探测（只读）：路径/版本/Chromium 判定/监听端口/CDP/URL scheme/UIA 统计。接手陌生 app 先跑它。',
        kind: 'probe',
        readOnly: true,
        inputSchema: {
            type: 'object',
            properties: { app: { type: 'string', description: '应用名 / exe 名 / 完整路径' } },
            required: ['app'],
            additionalProperties: false,
        },
        build: (a) => [a.app],
    },
    {
        name: 'win_cdp',
        description: '对内嵌 Chromium（Electron/CEF/WebView2）走 CDP：list/snapshot/find/wait/mouse/insert/press/shot/eval/act。args 原样传给 cdp.js；mouse/insert/press/act 属写操作。',
        destructive: true,
        inputSchema: {
            type: 'object',
            properties: {
                port: { type: 'number', description: 'CDP 端口' },
                args: {
                    type: 'array',
                    items: { type: 'string' },
                    description: '例如 ["snapshot"] 或 ["eval","document.title"]',
                },
            },
            required: ['port', 'args'],
            additionalProperties: false,
        },
        kind: 'cdp',
        build: (a) => [String(a.port), ...(a.args || [])],
    },
];

// ───────────────────────── 子进程执行 ─────────────────────────

function runProcess(file, args, options = {}) {
    return new Promise((resolve) => {
        const started = Date.now();
        const child = spawn(file, args, {
            cwd: options.cwd || ROOT,
            windowsHide: true,
            env: process.env,
        });
        let stdout = '';
        let stderr = '';
        let killedByTimeout = false;
        const timer = setTimeout(() => {
            killedByTimeout = true;
            child.kill();
        }, options.timeout || TIMEOUT_MS);

        child.stdout.on('data', (d) => { stdout += d.toString('utf8'); });
        child.stderr.on('data', (d) => { stderr += d.toString('utf8'); });
        child.on('error', (err) => {
            clearTimeout(timer);
            resolve({ code: 127, stdout, stderr: stderr + String(err.message || err), ms: Date.now() - started });
        });
        child.on('close', (code) => {
            clearTimeout(timer);
            resolve({
                code: killedByTimeout ? 124 : (code === null ? 1 : code),
                stdout,
                stderr: killedByTimeout ? (stderr + '\n[timeout] 命令超时被终止') : stderr,
                ms: Date.now() - started,
            });
        });
    });
}

function runWin(args) {
    return runProcess(POWERSHELL, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', WIN_PS1, ...args]);
}

function runProbe(args) {
    return runProcess(POWERSHELL, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', PROBE_PS1, ...args]);
}

function runCdp(args) {
    return runProcess(process.execPath, [CDP_JS, ...args], { cwd: path.join(ROOT, 'scripts') });
}

function clip(text) {
    if (text.length <= MAX_OUTPUT) return { text, truncated: false };
    return { text: text.slice(0, MAX_OUTPUT) + '\n…（输出超过 ' + MAX_OUTPUT + ' 字符，已截断）', truncated: true };
}

// ───────────────────────── MCP 协议 ─────────────────────────

function send(message) {
    process.stdout.write(JSON.stringify(message) + '\n');
}

function sendResult(id, result) {
    send({ jsonrpc: '2.0', id, result });
}

function sendError(id, code, message, data) {
    send({ jsonrpc: '2.0', id, error: { code, message, ...(data ? { data } : {}) } });
}

function toolDescriptor(tool) {
    const annotations = {
        readOnlyHint: Boolean(tool.readOnly),
        destructiveHint: Boolean(tool.destructive),
        idempotentHint: Boolean(tool.readOnly),
        openWorldHint: true,
    };
    return {
        name: tool.name,
        description: tool.description,
        inputSchema: tool.inputSchema,
        annotations,
    };
}

async function callTool(name, args) {
    const tool = TOOLS.find((t) => t.name === name);
    if (!tool) {
        return { isError: true, content: [{ type: 'text', text: '未知工具: ' + name }] };
    }
    const missing = (tool.inputSchema.required || []).filter((key) => args[key] === undefined || args[key] === null);
    if (missing.length > 0) {
        return { isError: true, content: [{ type: 'text', text: '缺少必填参数: ' + missing.join(', ') }] };
    }

    const argv = tool.build(args);
    const commandLine = tool.kind === 'probe'
        ? 'probe ' + argv.join(' ')
        : tool.kind === 'cdp'
            ? 'cdp.js ' + argv.join(' ')
            : 'win ' + argv.join(' ');

    const r = tool.kind === 'probe'
        ? await runProbe(argv)
        : tool.kind === 'cdp'
            ? await runCdp(argv)
            : await runWin(argv);

    const merged = ['[exit=' + r.code + '] ' + commandLine, r.stdout.trimEnd(), r.stderr.trim() ? '--- stderr ---\n' + r.stderr.trimEnd() : '']
        .filter(Boolean)
        .join('\n');
    const clipped = clip(merged);
    const isError = r.code !== 0;

    return {
        isError,
        content: [{ type: 'text', text: clipped.text }],
        structuredContent: {
            exit_code: r.code,
            duration_ms: r.ms,
            command: commandLine,
            truncated: clipped.truncated,
        },
    };
}

async function handleMessage(msg) {
    const hasId = msg.id !== undefined && msg.id !== null;
    const method = msg.method;
    const params = msg.params || {};

    if (!method) {
        if (hasId) sendError(msg.id, -32600, 'Invalid Request');
        return;
    }

    if (!hasId) {
        // 通知（如 notifications/initialized）不需要响应。
        if (method === 'notifications/initialized') {
            process.stderr.write('[winhand-use-mcp] client initialized\n');
        }
        return;
    }

    switch (method) {
        case 'initialize': {
            const requested = params.protocolVersion;
            const protocolVersion = SUPPORTED_PROTOCOLS.includes(requested) ? requested : DEFAULT_PROTOCOL;
            sendResult(msg.id, {
                protocolVersion,
                capabilities: { tools: { listChanged: false } },
                serverInfo: { name: 'winhand-use', version: SERVER_VERSION },
                instructions:
                    'Windows 桌面操控工具。先 win_doctor 自检，再 win_probe 选层：L0 CDP/CLI → L1 UIA（win_ax/win_axset/win_axpress）→ L2 坐标（win_op，先 dry）→ L3 截图（win_shot）。读操作不打扰用户；写操作前确认停手线，写后用截图或读回验证。',
            });
            return;
        }
        case 'ping':
            sendResult(msg.id, {});
            return;
        case 'tools/list':
            sendResult(msg.id, { tools: TOOLS.map(toolDescriptor) });
            return;
        case 'tools/call': {
            const name = params.name;
            if (!name) {
                sendError(msg.id, -32602, 'tools/call 缺少 name');
                return;
            }
            try {
                const result = await callTool(name, params.arguments || {});
                sendResult(msg.id, result);
            } catch (err) {
                sendResult(msg.id, {
                    isError: true,
                    content: [{ type: 'text', text: '工具执行异常: ' + String(err && err.message ? err.message : err) }],
                });
            }
            return;
        }
        case 'resources/list':
            sendResult(msg.id, { resources: [] });
            return;
        case 'prompts/list':
            sendResult(msg.id, { prompts: [] });
            return;
        default:
            sendError(msg.id, -32601, 'Method not found: ' + method);
    }
}

let buffer = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
    buffer += chunk;
    let index;
    while ((index = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, index).trim();
        buffer = buffer.slice(index + 1);
        if (!line) continue;
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (err) {
            sendError(null, -32700, 'Parse error');
            continue;
        }
        handleMessage(msg).catch((err) => {
            process.stderr.write('[winhand-use-mcp] handler error: ' + String(err) + '\n');
        });
    }
});
process.stdin.on('end', () => process.exit(0));

process.stderr.write('[winhand-use-mcp] ready: ' + TOOLS.length + ' tools, root=' + ROOT + '\n');
