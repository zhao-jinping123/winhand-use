#!/usr/bin/env node
// MCP Server 自测：走完整的 initialize → tools/list → tools/call(win_doctor) 流程。
// stdout 打印一行结果，失败退出码 1；CI 与本地都用它做冒烟。
'use strict';

const { spawn } = require('child_process');
const path = require('path');

const SERVER = path.join(__dirname, 'server.js');
const TIMEOUT_MS = Number(process.env.WINHAND_MCP_SELFTEST_TIMEOUT_MS || 180000);

function fail(message) {
    console.error('MCP selftest FAILED: ' + message);
    process.exit(1);
}

const server = spawn(process.execPath, [SERVER], {
    stdio: ['pipe', 'pipe', 'pipe'],
    windowsHide: true,
});

let buffer = '';
const pending = new Map();
let nextId = 1;

server.stderr.on('data', (d) => process.stderr.write(d));
server.stdout.on('data', (chunk) => {
    buffer += chunk.toString('utf8');
    let index;
    while ((index = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, index).trim();
        buffer = buffer.slice(index + 1);
        if (!line) continue;
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (err) {
            continue;
        }
        if (msg.id !== undefined && pending.has(msg.id)) {
            pending.get(msg.id)(msg);
            pending.delete(msg.id);
        }
    }
});
server.on('error', (err) => fail('无法启动 server.js: ' + err.message));

function call(method, params = {}) {
    return new Promise((resolve, reject) => {
        const id = nextId++;
        const timer = setTimeout(() => {
            pending.delete(id);
            reject(new Error('调用超时: ' + method));
        }, TIMEOUT_MS);
        pending.set(id, (msg) => {
            clearTimeout(timer);
            if (msg.error) reject(new Error(method + ' 返回错误: ' + JSON.stringify(msg.error)));
            else resolve(msg.result);
        });
        server.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
    });
}

(async () => {
    const init = await call('initialize', {
        protocolVersion: '2025-06-18',
        capabilities: {},
        clientInfo: { name: 'winhand-selftest', version: '1.0.0' },
    });
    if (!init || !init.serverInfo || init.serverInfo.name !== 'winhand-use') {
        fail('initialize 返回的 serverInfo 不正确');
    }

    const list = await call('tools/list');
    const tools = (list && list.tools) || [];
    if (tools.length < 10) fail('工具数量过少: ' + tools.length);
    if (!tools.some((t) => t.name === 'win_see' && t.inputSchema)) {
        fail('win_see 工具定义缺失');
    }

    const doctor = await call('tools/call', { name: 'win_doctor', arguments: {} });
    const text = (doctor.content && doctor.content[0] && doctor.content[0].text) || '';
    const exitCode = doctor.structuredContent && doctor.structuredContent.exit_code;
    if (exitCode !== 0 || !text.includes('doctor=done')) {
        fail('win_doctor 未通过: exit=' + exitCode);
    }

    const windows = await call('tools/call', { name: 'win_windows', arguments: {} });
    const windowsText = (windows.content && windows.content[0] && windows.content[0].text) || '';
    if (!windowsText.includes('窗口数=')) {
        fail('win_windows 未返回窗口列表');
    }

    console.log('MCP selftest OK: ' + tools.length + ' tools, protocol=' + init.protocolVersion + ', win_doctor + win_windows 通过');
    server.kill();
    process.exit(0);
})().catch((err) => fail(err.message));
