// Dart VM CPU sample poller: every interval, pulls getCpuSamples for the
// recent window on every non-system isolate and prints the hottest
// inclusive function names. Usage: node sampler-cpu.js <ws-uri> [windowMs]
const uri = process.argv[2];
if (!uri) {
  console.error('usage: node sampler-cpu.js ws://127.0.0.1:PORT/TOKEN=/ws [windowMs]');
  process.exit(2);
}
const windowMs = Number(process.argv[3] || 2000);

const ws = new WebSocket(uri);
let nextId = 1;
const pending = new Map();
function rpc(method, params) {
  return new Promise((res, rej) => {
    const id = String(nextId++);
    pending.set(id, { res, rej });
    ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
    setTimeout(() => {
      if (pending.has(id)) {
        pending.delete(id);
        rej(new Error('timeout ' + method));
      }
    }, 10000);
  });
}
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    if (m.error) pending.get(m.id).rej(new Error(m.error.message));
    else pending.get(m.id).res(m.result);
    pending.delete(m.id);
  }
};

async function main() {
  await new Promise((r, j) => {
    ws.onopen = r;
    ws.onerror = (e) => j(new Error('ws error'));
  });
  console.log('[sampler-cpu] connected');
  while (true) {
    const t = new Date().toISOString().slice(11, 23);
    let vm;
    try {
      vm = await rpc('getVM', {});
    } catch (e) {
      console.log(`[${t}] getVM failed: ${e.message}`);
      await new Promise((r) => setTimeout(r, 1000));
      continue;
    }
    const now = await rpc('getVM', {}).then((v) => Date.now()).catch(() => Date.now());
    for (const iso of vm.isolates.filter((i) => !i.isSystemIsolate)) {
      try {
        const origin = (now - windowMs) * 1000;
        const s = await rpc('getCpuSamples', {
          isolateId: iso.id,
          timeOriginMicros: origin,
          timeExtentMicros: windowMs * 1000,
        });
        const samples = s.samples || [];
        const funcs = new Map();
        for (const f of s.functions || []) funcs.set(f.id, f.name);
        if (samples.length === 0) continue;
        const inclusive = new Map();
        const exclusive = new Map();
        for (const sample of samples) {
          const stack = sample.stack || [];
          const seen = new Set();
          for (let i = 0; i < stack.length; i++) {
            const name = funcs.get(stack[i]) || `#${stack[i]}`;
            if (!seen.has(name)) {
              seen.add(name);
              inclusive.set(name, (inclusive.get(name) || 0) + 1);
            }
            if (i === stack.length - 1) {
              exclusive.set(name, (exclusive.get(name) || 0) + 1);
            }
          }
        }
        const top = (m, n) =>
          [...m.entries()].sort((a, b) => b[1] - a[1]).slice(0, n)
            .map(([k, v]) => `${v} ${k}`).join(' | ');
        console.log(
          `[${t}] ${iso.name}: ${samples.length} samples/${windowMs}ms\n` +
          `    exc: ${top(exclusive, 6)}\n` +
          `    inc: ${top(inclusive, 8)}`,
        );
      } catch (e) {
        console.log(`[${t}] ${iso.name} getCpuSamples failed: ${e.message}`);
      }
    }
    await new Promise((r) => setTimeout(r, windowMs));
  }
}
main().catch((e) => {
  console.error('sampler-cpu exit: ' + e.message);
  process.exit(1);
});
