const uri = process.argv[2];
const ws = new WebSocket(uri);
let nextId = 1;
const pending = new Map();
function rpc(method, params, timeoutMs=60000) {
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
  const vm = await rpc('getVM', {});
  const main = vm.isolates.find((i) => i.name === 'main');
  if (!main) { console.log('no main isolate'); process.exit(1); }
  // reset counters, wait 3s, then read — the delta is the live allocation rate
  await rpc('getAllocationProfile', { isolateId: main.id, gc: false, reset: true });
  await new Promise((r) => setTimeout(r, 3000));
  const prof = await rpc('getAllocationProfile', { isolateId: main.id, gc: false });
  const rows = [...(prof.members || [])]
      .sort((a, b) => (b.newSpaceCapacity ?? 0) + (b.oldSpaceCapacity ?? 0) - ((a.newSpaceCapacity ?? 0) + (a.oldSpaceCapacity ?? 0)));
  console.log(`heap: usage=${(prof.memoryUsage?.heapUsage ?? 0)/1048576|0}MB external=${(prof.memoryUsage?.externalUsage ?? 0)/1048576|0}MB`);
  console.log('top classes by accumulated allocation (3s window):');
  for (const c of rows.slice(0, 25)) {
    const cls = c.classRef?.name ?? '?';
    console.log(`  new=${String(c.newSpaceCapacity ?? 0).padStart(9)} old=${String(c.oldSpaceCapacity ?? 0).padStart(9)}  ${cls}`);
  }
  ws.close(); process.exit(0);
}
main().catch((e) => { console.error('exit: ' + e.message); process.exit(1); });
