// One-shot stack probe: prints getStack frames for every non-system isolate.
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
    }, 8000);
  });
}
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id).res(m.result); pending.delete(m.id); }
};
async function main() {
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = () => j(new Error('ws')); });
  const vm = await rpc('getVM', {});
  for (const iso of vm.isolates.filter((i) => !i.isSystemIsolate)) {
    try {
      const st = await rpc('getStack', { isolateId: iso.id });
      const frames = (st.frames || []).map((f) => `${f.function ?? '?'}`).slice(0, 14);
      const asyncF = (st.asyncCausalFrames || []).map((f) => `${f.function ?? '?'}`).slice(0, 14);
      console.log(`== ${iso.name} ==`);
      console.log('  sync : ' + (frames.join(' <- ') || '(empty)'));
      console.log('  async: ' + (asyncF.join(' <- ') || '(empty)'));
    } catch (e) {
      console.log(`== ${iso.name} == getStack failed: ${e.message}`);
    }
  }
  ws.close();
  process.exit(0);
}
main().catch((e) => { console.error('probe exit: ' + e.message); process.exit(1); });
