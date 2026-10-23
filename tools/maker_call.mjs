#!/usr/bin/env node
/**
 * Maker MCP 直连兜底通道
 *
 * 用途：当 WorkBuddy 会话尚未挂载 taptap-maker 工具（例如会话早于安装/重启创建），
 * 仍可通过本脚本直接对 Maker MCP server 做 stdio JSON-RPC 调用。
 *
 * 用法：
 *   node tools/maker_call.mjs list
 *   node tools/maker_call.mjs call maker_status_lite '{"target_dir":"/abs/path","detail":true}'
 *   node tools/maker_call.mjs schema maker_status_lite
 *
 * 实现要点：
 *  - initialize 之后必须发 notifications/initialized，否则 server 不处理后续请求
 *  - stdout 为换行分隔的 JSON-RPC，需按行切分解析
 *  - 完成后必须 kill 子进程：该 server 在 stdin 关闭前不会自动退出
 */
import { spawn } from 'node:child_process';

const NODE = process.env.MAKER_NODE
  || '/Users/ruoyan/.workbuddy/binaries/node/versions/22.22.2-6/bin/node';
const JS = process.env.MAKER_JS
  || '/Users/ruoyan/.taptap-maker/mcp-runtime/0.0.38/dist/maker.js';
const TIMEOUT_MS = Number(process.env.MAKER_TIMEOUT || 120000);

const [mode, arg1, arg2] = process.argv.slice(2);

const child = spawn(NODE, [JS], {
  env: { ...process.env, TAPTAP_MCP_CLIENT_IDE: 'workbuddy' },
  stdio: ['pipe', 'pipe', 'pipe'],
});

let buf = '';
let finished = false;
let toolsCache = null;

function send(obj) {
  child.stdin.write(JSON.stringify(obj) + '\n');
}

function finish(code) {
  if (finished) return;
  finished = true;
  try { child.kill(); } catch (_) { /* 已退出 */ }
  process.exit(code);
}

function handle(msg) {
  if (msg.id === 1) {                                   // initialize 完成
    send({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} });
    if (mode === 'list') {
      send({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} });
    } else if (mode === 'schema') {
      send({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} });
    } else if (mode === 'call') {
      send({ jsonrpc: '2.0', id: 3, method: 'tools/call',
             params: { name: arg1, arguments: arg2 ? JSON.parse(arg2) : {} } });
    } else {
      console.error('用法：node tools/maker_call.mjs list|schema <tool>|call <tool> <json>');
      finish(2);
    }
    return;
  }

  if (msg.id === 2) {                                   // tools/list 结果
    const tools = (msg.result && msg.result.tools) || [];
    toolsCache = tools;
    if (mode === 'list') {
      console.log('TOOLS_COUNT=' + tools.length);
      for (const t of tools) console.log(t.name);
      finish(0);
    } else {
      const t = tools.find((x) => x.name === arg1);
      if (!t) { console.error('未找到工具：' + arg1); finish(3); }
      console.log(JSON.stringify(t.inputSchema, null, 1));
      finish(0);
    }
    return;
  }

  if (msg.id === 3) {                                   // tools/call 结果
    if (msg.error) {
      console.error('RPC ERROR: ' + JSON.stringify(msg.error));
      finish(4);
    }
    const c = msg.result && msg.result.content;
    if (Array.isArray(c)) {
      for (const part of c) {
        if (part.type === 'text') console.log(part.text);
        else console.log(JSON.stringify(part));
      }
    } else {
      console.log(JSON.stringify(msg.result, null, 1));
    }
    if (msg.result && msg.result.isError) finish(5);
    finish(0);
  }
}

child.stdout.on('data', (d) => {
  buf += d.toString();
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i);
    buf = buf.slice(i + 1);
    if (!line.trim()) continue;
    let m;
    try { m = JSON.parse(line); } catch (_) { continue; }
    handle(m);
  }
});

child.stderr.on('data', (d) => {
  const s = d.toString().trim();
  if (s) process.stderr.write('[maker] ' + s.slice(0, 400) + '\n');
});

child.on('exit', (code) => {
  if (!finished) {
    finished = true;
    process.stderr.write('[maker] server 提前退出，code=' + code + '\n');
    process.exit(code == null ? 1 : code);
  }
});

send({
  jsonrpc: '2.0', id: 1, method: 'initialize',
  params: {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'workbuddy-direct', version: '1.0' },
  },
});

setTimeout(() => {
  process.stderr.write('[maker] 超时（' + TIMEOUT_MS + 'ms）\n');
  finish(6);
}, TIMEOUT_MS);
