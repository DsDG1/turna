// Continuous monitor: watches isolates, allocation profile and CPU samples,
// logging a timeline to monitor.log. During a main-isolate spin the cpu
// samples (if the profiler is on) name the hot function directly; the
// allocation profile distinguishes an allocation loop (heap climbing) from a
// pure compute loop (heap flat).
const uri = process.argv[2];
const ws = new WebSocket(uri);
let nextId = 1;
const pending = new Map();
function rpc(method, params) {
  return new Promise((res, rej) => {
    const id = String(nextId++);
    pending.set(id, { res, rej });
    ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
    setTimeout(() => {
      if (pending.has(id)) { pending.delete(id); rej(new Error('timeout ' + method)); }
    }, 12000);
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
const stamp = () => new Date().toISOString().slice(11, 23);
async function main() {
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = () => j(new Error('ws')); });
  console.log(`[${stamp()}] monitor connected`);
  let lastHeap = -1;
  let deadCycles = 0;
let freezeStrikes = 0;
  while (true) {
    try {
      const t0 = Date.now();
      const vm = await Promise.race([
        rpc('getVM', {}),
        new Promise((_, rej) => setTimeout(() => rej(new Error('SLOW')), 10000)),
      ]);
      const latency = Date.now() - t0;
      if (latency > 1500) deadCycles++; else deadCycles = 0;
      const names = vm.isolates.filter((i) => !i.isSystemIsolate).map((i) => i.name);
      const main = vm.isolates.find((i) => i.name === 'main');
      let heapLine = '';
      if (main) {
        try {
          const prof = await rpc('getAllocationProfile', { isolateId: main.id });
          const mu = prof.memoryUsage;
          if (mu) {
            const total = mu.heapUsage ?? 0;
            heapLine = `heap=${(total / 1048576).toFixed(1)}MB`;
            if (lastHeap >= 0) heapLine += ` Δ${((total - lastHeap) / 1048576).toFixed(1)}MB`;
            lastHeap = total;
          }
        } catch (_) {}
      }
      // CPU samples for the recent window
      let cpuLine = '';
      for (const iso of vm.isolates.filter((i) => !i.isSystemIsolate && i.name === 'main')) {
        try {
          const s = await rpc('getCpuSamples', {
            isolateId: iso.id,
            timeOriginMicros: (Date.now() - 3000) * 1000,
            timeExtentMicros: 3000 * 1000,
          });
          const samples = s.samples || [];
          if (samples.length > 0) {
            const funcs = new Map();
            for (const f of s.functions || []) funcs.set(f.id, f.name);
            const inc = new Map();
            for (const sample of samples) {
              const seen = new Set();
              for (const id of sample.stack || []) {
                const n = funcs.get(id) || `#${id}`;
                if (!seen.has(n)) { seen.add(n); inc.set(n, (inc.get(n) || 0) + 1); }
              }
            }
            const top = [...inc.entries()].sort((a, b) => b[1] - a[1]).slice(0, 6)
                .map(([k, v]) => `${v} ${k}`).join(' | ');
            cpuLine = `\n    CPU ${samples.length}/3000ms inc: ${top}`;
          } else {
            cpuLine = `\n    CPU 0 samples (profiler off?)`;
          }
        } catch (e) {
          cpuLine = `\n    cpu failed: ${e.message}`;
        }
      }
      console.log(
        `[${stamp()}] rpc=${latency}ms${deadCycles > 2 ? ' *** UNRESPONSIVE-ish ***' : ''} ` +
        `isolates=[${names.join(', ')}] ${heapLine}${cpuLine}`,
      );
      if (latency > 1500 || deadCycles > 0) {
        freezeStrikes++;
        if (freezeStrikes >= 1) {
          console.log(`[${stamp()}] FREEZE DETECTED — dumping VM timeline NOW`);
          try {
            const t = await rpc('getVMTimeline', {});
            require('fs').writeFileSync('timeline-frozen.json', JSON.stringify(t));
            console.log(`[${stamp()}] timeline-frozen.json written: ${(t.traceEvents || []).length} events`);
          } catch (e2) {
            console.log(`[${stamp()}] timeline dump failed: ${e2.message}`);
          }
          try {
            const vm2 = await rpc('getVM', {});
            const m2 = vm2.isolates.find((i) => i.name === 'main');
            if (m2) {
              const st = await rpc('getStack', { isolateId: m2.id });
              require('fs').writeFileSync('stack-frozen.json', JSON.stringify(st, null, 1));
              console.log(`[${stamp()}] stack-frozen.json written`);
            }
          } catch (_) {}
          process.exit(0);
        }
      }
      deadCycles = 0;
    } catch (e) {
      console.log(`[${stamp()}] VM service problem: ${e.message}${e.message.includes('SLOW') ? ' <-- FREEZE ONSET (rpc strain)' : ''}`);
      deadCycles++;
      if (deadCycles >= 2) {
        console.log(`[${stamp()}] FREEZE DETECTED (catch path) — dumping VM timeline NOW`);
        try {
          const t = await rpc('getVMTimeline', {});
          require('fs').writeFileSync('timeline-frozen.json', JSON.stringify(t));
          console.log(`[${stamp()}] timeline-frozen.json written: ${(t.traceEvents || []).length} events`);
        } catch (e2) {
          console.log(`[${stamp()}] timeline dump failed: ${e2.message}`);
        }
        process.exit(0);
      }
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
}
main().catch((e) => { console.error('monitor exit: ' + e.message); process.exit(1); });
