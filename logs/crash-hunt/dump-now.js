
const uri = process.argv[2];
const ws = new WebSocket(uri);
let nextId = 1;
const pending = new Map();
function rpc(method, params, timeoutMs=150000) {
  return new Promise((res, rej) => {
    const id = String(nextId++);
    pending.set(id, { res, rej });
    ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
    setTimeout(() => { if (pending.has(id)) { pending.delete(id); rej(new Error('timeout ' + method)); } }, timeoutMs);
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
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = () => j(new Error('ws')); });
  console.log('connected, dumping timeline (patient)...');
  try {
    const t = await rpc('getVMTimeline', {});
    require('fs').writeFileSync('timeline-frozen.json', JSON.stringify(t));
    console.log('timeline-frozen.json:', (t.traceEvents || []).length, 'events');
  } catch (e) { console.log('timeline failed: ' + e.message); }
  try {
    const vm = await rpc('getVM', {}, 30000);
    const m = vm.isolates.find((i) => i.name === 'main');
    if (m) {
      const st = await rpc('getStack', { isolateId: m.id }, 60000);
      require('fs').writeFileSync('stack-frozen.json', JSON.stringify(st, null, 1));
      console.log('stack-frozen.json written');
    }
  } catch (e) { console.log('stack failed: ' + e.message); }
  ws.close(); process.exit(0);
}
main().catch((e) => { console.error('exit: ' + e.message); process.exit(1); });
