#!/usr/bin/env node
/**
 * deveco-cli-mcp.mjs — DevEco CLI → MCP bridge for WorkBuddy.
 *
 * Zero-dependency stdio MCP server (newline-delimited JSON-RPC 2.0) that
 * exposes the Huawei DevEco Studio command-line tools to WorkBuddy agents:
 *
 *   hdc      HarmonyOS Device Connector — devices, install, shell, files, hilog
 *   hvigorw  OpenHarmony build tool    — assembleHap, clean, tasks
 *   ohpm     OpenHarmony package mgr   — install, list
 *
 * Discovery order for DEVECO_HOME (first existing wins):
 *   $DEVECO_HOME → D:\DevEco Studio → C:\Program Files\Huawei\DevEco Studio
 * DEVECO_SDK_HOME overrides the sdk dir; DEVECO_OHOS_PROJECT overrides the
 * default ohos project dir.
 *
 * Registered in ~/.workbuddy/mcp.json as server "deveco-cli". After adding the
 * entry, enable it once via WorkBuddy → connector management → custom
 * connectors → Trust.
 *
 * Tools:
 *   deveco_cli_info    resolved paths + CLI versions + default project
 *   deveco_hdc_targets list connected devices/emulators
 *   deveco_hdc         generic hdc passthrough (optional target)
 *   deveco_hvigorw     generic hvigorw passthrough (tasks + -p props)
 *   deveco_ohpm        generic ohpm passthrough
 */

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { createInterface } from "node:readline";

const SERVER_NAME = "deveco-cli";
const SERVER_VERSION = "1.0.0";
const DEFAULT_PROTOCOL = "2024-11-05";
const MAX_OUTPUT = 30000; // chars returned per call; keeps agent context sane

// ---------------------------------------------------------------------------
// DevEco CLI discovery
// ---------------------------------------------------------------------------

function firstFile(paths) {
  for (const p of paths) {
    if (p && existsSync(p)) return p;
  }
  return null;
}

function discoverDeveco() {
  const homes = [
    process.env.DEVECO_HOME,
    "D:\\DevEco Studio",
    "C:\\Program Files\\Huawei\\DevEco Studio",
    "D:\\DevEcoStudio",
  ].filter(Boolean);

  const home = homes.find((p) => existsSync(p)) || null;
  const sdk = process.env.DEVECO_SDK_HOME || (home ? join(home, "sdk") : null);

  const hdc = firstFile([
    sdk && join(sdk, "default", "openharmony", "toolchains", "hdc.exe"),
    home && join(home, "sdk", "default", "openharmony", "toolchains", "hdc.exe"),
  ]);
  const hvigorw = firstFile([home && join(home, "tools", "hvigor", "bin", "hvigorw.bat")]);
  const ohpm = firstFile([home && join(home, "tools", "ohpm", "bin", "ohpm.bat")]);

  return { home, sdk, hdc, hvigorw, ohpm };
}

function defaultProject() {
  return process.env.DEVECO_OHOS_PROJECT || "D:\\program\\Turna\\Turna\\ohos";
}

// ---------------------------------------------------------------------------
// Command execution
// ---------------------------------------------------------------------------

function quoteForCmd(arg) {
  const s = String(arg);
  if (!/[\s"&|<>^()!]/.test(s)) return s;
  return '"' + s.replace(/"/g, '""') + '"';
}

function killTree(pid) {
  if (!pid) return;
  try {
    spawn("taskkill", ["/pid", String(pid), "/T", "/F"], {
      shell: false,
      windowsHide: true,
      stdio: "ignore",
    });
  } catch {
    /* process already gone */
  }
}

function runCommand(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    const isBatch = /\.(bat|cmd)$/i.test(cmd);
    const cwd = opts.cwd && existsSync(opts.cwd) ? opts.cwd : process.cwd();

    let child;
    if (isBatch) {
      // .bat cannot be spawned with an args array on Windows; build one fully
      // quoted command line and let cmd.exe parse it.
      const line = [cmd, ...args].map(quoteForCmd).join(" ");
      child = spawn(line, {
        cwd,
        env: { ...process.env, ...(opts.env || {}) },
        shell: true,
        windowsHide: true,
      });
    } else {
      child = spawn(cmd, args, {
        cwd,
        env: { ...process.env, ...(opts.env || {}) },
        shell: false,
        windowsHide: true,
      });
    }

    let stdout = "";
    let stderr = "";
    const cap = 8 * 1024 * 1024;
    const tail = (buf, chunk) => {
      buf += chunk;
      return buf.length > cap ? buf.slice(buf.length - cap / 2) : buf;
    };
    child.stdout.on("data", (d) => { stdout = tail(stdout, d); });
    child.stderr.on("data", (d) => { stderr = tail(stderr, d); });

    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      killTree(child.pid);
    }, opts.timeoutMs || 600000);
    if (typeof timer.unref === "function") timer.unref();

    child.on("error", (err) => {
      clearTimeout(timer);
      resolve({ code: -1, stdout, stderr: String(err?.message || err), timedOut });
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ code: timedOut ? -1 : code ?? -1, stdout, stderr, timedOut });
    });
  });
}

// ---------------------------------------------------------------------------
// Result formatting
// ---------------------------------------------------------------------------

function truncate(text) {
  if (text.length <= MAX_OUTPUT) return text;
  const half = Math.floor(MAX_OUTPUT / 2);
  return `${text.slice(0, half)}\n\n... [truncated ${text.length - MAX_OUTPUT} chars] ...\n\n${text.slice(text.length - half)}`;
}

function textResult(text, isError = false) {
  return { content: [{ type: "text", text }], ...(isError ? { isError: true } : {}) };
}

function errText(text) {
  return textResult(text, true);
}

function execResult(label, r) {
  const sections = [];
  if (r.stdout.trim()) sections.push(r.stdout.trim());
  if (r.stderr.trim()) sections.push(`[stderr]\n${r.stderr.trim()}`);
  if (sections.length === 0) sections.push("(no output)");
  const note = r.timedOut ? "\n(TIMEOUT — process tree killed)" : "";
  return textResult(
    truncate(`$ ${label}\nexit code: ${r.code}${note}\n\n${sections.join("\n")}`),
    r.code !== 0,
  );
}

function missingTool(what, de) {
  return errText(
    `${what} CLI not found.\nDEVECO_HOME=${de.home || "(unset)"}\n` +
      `Install DevEco Studio or set DEVECO_HOME / DEVECO_SDK_HOME.`,
  );
}

function toStrArray(v) {
  if (v === undefined || v === null) return [];
  const arr = Array.isArray(v) ? v : [v];
  return arr.map((x) => String(x)).filter((x) => x.length > 0);
}

// ---------------------------------------------------------------------------
// Tool implementations
// ---------------------------------------------------------------------------

async function callTool(name, rawArgs) {
  const a = rawArgs || {};
  const de = discoverDeveco();

  switch (name) {
    case "deveco_cli_info": {
      const lines = [
        `DEVECO_HOME:     ${de.home || "(not found)"}`,
        `DEVECO_SDK_HOME: ${de.sdk || "(not found)"}`,
        `hdc:             ${de.hdc || "(not found)"}`,
        `hvigorw:         ${de.hvigorw || "(not found)"}`,
        `ohpm:            ${de.ohpm || "(not found)"}`,
        `ohos project:    ${defaultProject()}${existsSync(defaultProject()) ? "" : " (missing)"}`,
      ];
      if (de.hdc) {
        const r = await runCommand(de.hdc, ["-v"], { timeoutMs: 15000 });
        const first = (r.stdout.trim() || r.stderr.trim()).split("\n")[0] || "(no output)";
        lines.push(`hdc version:     ${first}`);
      }
      if (de.ohpm) {
        const r = await runCommand(de.ohpm, ["-v"], { timeoutMs: 30000 });
        const first = (r.stdout.trim() || r.stderr.trim()).split("\n")[0] || "(no output)";
        lines.push(`ohpm version:    ${first}`);
      }
      if (de.hvigorw && existsSync(defaultProject())) {
        const r = await runCommand(de.hvigorw, ["--version"], {
          cwd: defaultProject(),
          timeoutMs: 60000,
        });
        const first = (r.stdout.trim() || r.stderr.trim()).split("\n").slice(-1)[0] || "(no output)";
        lines.push(`hvigorw version: ${first}`);
      }
      return textResult(lines.join("\n"));
    }

    case "deveco_hdc_targets": {
      if (!de.hdc) return missingTool("hdc", de);
      const r = await runCommand(de.hdc, ["list", "targets"], { timeoutMs: 15000 });
      return execResult("hdc list targets", r);
    }

    case "deveco_hdc": {
      if (!de.hdc) return missingTool("hdc", de);
      const argvIn = toStrArray(a.args);
      if (argvIn.length === 0) {
        return errText('args must be a non-empty array, e.g. ["shell", "hilog"]');
      }
      const argv = a.target ? ["-t", String(a.target), ...argvIn] : argvIn;
      const r = await runCommand(de.hdc, argv, { timeoutMs: a.timeoutMs || 120000 });
      return execResult(`hdc ${argv.join(" ")}`, r);
    }

    case "deveco_hvigorw": {
      if (!de.hvigorw) return missingTool("hvigorw", de);
      const tasks = toStrArray(a.tasks);
      if (tasks.length === 0) {
        return errText('tasks must be a non-empty array, e.g. ["assembleHap"]');
      }
      const props = toStrArray(a.props);
      const project = a.project || defaultProject();
      if (!existsSync(project)) {
        return errText(`ohos project dir not found: ${project}`);
      }
      const argv = [...tasks];
      for (const p of props) argv.push("-p", p);
      const r = await runCommand(de.hvigorw, argv, {
        cwd: project,
        timeoutMs: a.timeoutMs || 600000,
      });
      return execResult(`hvigorw ${argv.join(" ")}  (cwd: ${project})`, r);
    }

    case "deveco_ohpm": {
      if (!de.ohpm) return missingTool("ohpm", de);
      const argv = toStrArray(a.args);
      if (argv.length === 0) {
        return errText('args must be a non-empty array, e.g. ["install", "--all"]');
      }
      const project = a.project || defaultProject();
      if (!existsSync(project)) {
        return errText(`ohos project dir not found: ${project}`);
      }
      const r = await runCommand(de.ohpm, argv, {
        cwd: project,
        timeoutMs: a.timeoutMs || 300000,
      });
      return execResult(`ohpm ${argv.join(" ")}  (cwd: ${project})`, r);
    }

    default:
      return errText(`unknown tool: ${name}`);
  }
}

// ---------------------------------------------------------------------------
// Tool catalog
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: "deveco_cli_info",
    description:
      "Show resolved DevEco Studio CLI paths (DEVECO_HOME, hdc, hvigorw, ohpm), their versions, and the default ohos project dir. Run this first to verify the DevEco CLI import is healthy.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "deveco_hdc_targets",
    description:
      "List connected HarmonyOS devices/emulators (hdc list targets). The serials returned can be passed as the 'target' argument of deveco_hdc.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "deveco_hdc",
    description:
      "Run any hdc (HarmonyOS Device Connector) command. Common uses: shell <cmd> (run on device), install <hap path>, uninstall <bundle name>, file send <local> <remote>, file recv <remote> <local>, fport/rport (port forward). Pass target=<serial> to select a device.",
    inputSchema: {
      type: "object",
      properties: {
        args: {
          type: "array",
          items: { type: "string" },
          description: 'hdc arguments, e.g. ["shell", "hilog"] or ["install", "entry-debug.hap"]',
        },
        target: {
          type: "string",
          description: "device serial from deveco_hdc_targets; omit to let hdc pick the single device",
        },
        timeoutMs: { type: "number", description: "timeout in ms, default 120000" },
      },
      required: ["args"],
    },
  },
  {
    name: "deveco_hvigorw",
    description:
      "Run hvigorw (OpenHarmony build tool) tasks in an ohos project dir. WARNING for the Turna repo (AGENTS.md §9.1): HAP builds must go through the flutter fork SDK first (flutter build hap); bare hvigorw packaging fails once ohpm install has pruned plugin deps under entry/oh_modules, and it will not regenerate libapp.so / flutter_assets. Safe for clean, task listing and inspection.",
    inputSchema: {
      type: "object",
      properties: {
        tasks: {
          type: "array",
          items: { type: "string" },
          description: 'hvigorw task names, e.g. ["assembleHap"] or ["clean"]',
        },
        props: {
          type: "array",
          items: { type: "string" },
          description:
            'build properties as key=value; each is passed as -p key=value, e.g. ["product=default", "buildMode=debug"]',
        },
        project: {
          type: "string",
          description:
            "ohos project dir; defaults to $DEVECO_OHOS_PROJECT or D:\\program\\Turna\\Turna\\ohos",
        },
        timeoutMs: { type: "number", description: "timeout in ms, default 600000" },
      },
      required: ["tasks"],
    },
  },
  {
    name: "deveco_ohpm",
    description:
      "Run ohpm (OpenHarmony package manager) commands in an ohos project dir. Common uses: install --all, install <package> --save, list. NOTE: 'ohpm install' prunes plugin deps under entry/oh_modules without reinstalling them (Turna AGENTS.md §9.1) — in this repo always run it via the flutter fork's build, not standalone.",
    inputSchema: {
      type: "object",
      properties: {
        args: {
          type: "array",
          items: { type: "string" },
          description: 'ohpm arguments, e.g. ["install", "--all"]',
        },
        project: {
          type: "string",
          description:
            "ohos project dir; defaults to $DEVECO_OHOS_PROJECT or D:\\program\\Turna\\Turna\\ohos",
        },
        timeoutMs: { type: "number", description: "timeout in ms, default 300000" },
      },
      required: ["args"],
    },
  },
];

// ---------------------------------------------------------------------------
// JSON-RPC plumbing (stdio, newline-delimited)
// ---------------------------------------------------------------------------

function send(obj) {
  try {
    if (process.stdout.writable) process.stdout.write(JSON.stringify(obj) + "\n");
  } catch {
    /* EPIPE etc. — client gone */
  }
}

function result(id, payload) {
  send({ jsonrpc: "2.0", id, result: payload });
}

function rpcError(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

async function handleMessage(msg) {
  if (!msg || typeof msg !== "object") return;
  const { id, method, params } = msg;
  const isNotification = id === undefined || id === null;

  try {
    switch (method) {
      case "initialize":
        result(id, {
          protocolVersion: params?.protocolVersion || DEFAULT_PROTOCOL,
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
        });
        return;
      case "notifications/initialized":
      case "initialized":
        return; // notification — no response
      case "ping":
        if (!isNotification) result(id, {});
        return;
      case "tools/list":
        result(id, { tools: TOOLS });
        return;
      case "resources/list":
        if (!isNotification) result(id, { resources: [] });
        return;
      case "prompts/list":
        if (!isNotification) result(id, { prompts: [] });
        return;
      case "tools/call": {
        const name = params?.name;
        const tool = TOOLS.find((t) => t.name === name);
        if (!tool) {
          if (!isNotification) rpcError(id, -32602, `unknown tool: ${name}`);
          return;
        }
        const res = await callTool(name, params?.arguments || {});
        if (!isNotification) result(id, res);
        return;
      }
      default:
        if (!isNotification) rpcError(id, -32601, `method not found: ${method}`);
    }
  } catch (err) {
    if (!isNotification) rpcError(id, -32603, String(err?.stack || err?.message || err));
  }
}

// Serialize message handling: MCP messages must be processed in order and
// tools/call may be long-running (hvigorw builds).
const queue = [];
let busy = false;
let stdinEnded = false;
function pump() {
  if (busy) return;
  const next = queue.shift();
  if (!next) {
    // stdin closed and nothing left to do — the client is gone.
    if (stdinEnded) process.exit(0);
    return;
  }
  busy = true;
  handleMessage(next).finally(() => {
    busy = false;
    pump();
  });
}

const rl = createInterface({ input: process.stdin, terminal: false });
rl.on("line", (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  let msg;
  try {
    msg = JSON.parse(trimmed);
  } catch {
    return; // ignore unparseable input
  }
  queue.push(msg);
  pump();
});

rl.on("close", () => {
  stdinEnded = true;
  if (!busy && queue.length === 0) process.exit(0);
});

process.stdout.on("error", () => { /* client closed the pipe */ });
process.on("uncaughtException", (err) => {
  process.stderr.write(`[deveco-cli-mcp] uncaught: ${err?.stack || err}\n`);
});
