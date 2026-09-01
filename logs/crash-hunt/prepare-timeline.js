// Enable broad timeline recording, then dump the VM timeline on demand:
//   node prepare-timeline.js <ws-uri> arm     -> set flags, keep running
//   node prepare-timeline.js <ws-uri> dump    -> pull getVMTimeline to timeline-dump.json
const uri = process.argv[2];
const mode = process.argv[3] || 'arm';
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
    }, 60000);
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
  if (mode === 'arm') {
    const r = await rpc('setVMTimelineFlags', {
      recordedStreams: ['Dart', 'GC', 'Embedder', 'Isolate', 'VM', 'Compiler', 'Debugger'],
    });
    console.log('timeline flags set:', JSON.stringify(r).slice(0, 200));
    console.log('armed — reproduce the freeze now; then run dump');
    ws.close();
  } else {
    const t = await rpc('getVMTimeline', {});
    require('fs').writeFileSync('timeline-dump.json', JSON.stringify(t));
    console.log('timeline dumped:', (t.traceEvents || []).length, 'events');
    ws.close();
  }
  process.exit(0);
}
main().catch((e) => { console.error('exit: ' + e.message); process.exit(1); });
