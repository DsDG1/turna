// Deep probe: repeated pause/getStack/resume to catch the hot event, then
// a CPU-profiler window query. Usage: node deep-probe.js <ws-uri> [isolateName]
const uri = process.argv[2];
const wantName = process.argv[3] || 'main';
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
    }, 8000);
  });
}
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    pending.get(m.id).res(m.result || m.error || {});
    pending.delete(m.id);
  }
};
const seen = new Set();
function once(line) {
  if (seen.has(line)) return;
  seen.add(line);
  console.log(line);
}
async function main() {
  await new Promise((r, j) => {
    ws.onopen = r;
    ws.onerror = (e) => j(new Error('ws open failed'));
  });
  const vm = await rpc('getVM', {});
  const iso = vm.isolates.find((i) => i.name === wantName && !i.isSystemIsolate);
  if (!iso) throw new Error('isolate not found: ' + wantName);
  console.log('# probing isolate ' + iso.id);

  // Phase 1: pause-trap the hot event loop.
  for (let k = 0; k < 40; k++) {
    try {
      await rpc('pause', { isolateId: iso.id });
      const st = await rpc('getStack', { isolateId: iso.id });
      const frames = (st.frames || []).map(
        (f) => f.function && (f.function.name || f.function) || (f.code && f.code.name) || '?',
      );
      const asyncFrames = (st.asyncCausalFrames || []).map(
        (f) => f.function && (f.function.name || f.function) || (f.code && f.code.name) || '?',
      );
      once(
        'PAUSE#' + k + ' sync: ' + (frames.join('  <-  ') || '(idle)') +
          (asyncFrames.length ? '\n        async: ' + asyncFrames.join('  <-  ') : ''),
      );
      await rpc('resume', { isolateId: iso.id });
    } catch (e) {
      once('PAUSE#' + k + ' err ' + e.message);
    }
    await new Promise((r) => setTimeout(r, 150));
  }

  // Phase 2: CPU samples from the last 12 seconds.
  try {
    const now = Date.now();
    const origin = (now - 12000) * 1000;
    const extent = 12000 * 1000;
    const cs = await rpc('getCpuSamples', {
      isolateId: iso.id,
      timeOrigin: origin,
      timeExtent: extent,
    });
    console.log('# cpu samples: ' + (cs.samples ? cs.samples.length : 0));
    const codeNames = new Map();
    for (const c of cs.codes || []) {
      codeNames.set(c.id, c.name);
    }
    // Aggregate the LEAF frame of each sample.
    const leafCount = new Map();
    for (const s of cs.samples || []) {
      const stack = s.stack || [];
      if (!stack.length) continue;
      const leaf = codeNames.get(stack[stack.length - 1]) || '?';
      leafCount.set(leaf, (leafCount.get(leaf) || 0) + 1);
    }
    const top = [...leafCount.entries()].sort((a, b) => b[1] - a[1]).slice(0, 25);
    for (const [name, n] of top) console.log(String(n).padStart(6) + '  ' + name);
    // Also print the 3 hottest full stacks (deduped).
    const fullCount = new Map();
    for (const s of cs.samples || []) {
      const names = (s.stack || []).map((id) => codeNames.get(id) || '?');
      const key = names.join(' <- ');
      fullCount.set(key, (fullCount.get(key) || 0) + 1);
    }
    const topFull = [...fullCount.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);
    for (const [stack, n] of topFull) {
      console.log('--- ' + n + ' samples');
      console.log(stack);
    }
  } catch (e) {
    console.log('# cpu samples failed: ' + e.message);
  }
  process.exit(0);
}
main().catch((e) => {
  console.error('deep-probe exit: ' + e.message);
  process.exit(1);
});
