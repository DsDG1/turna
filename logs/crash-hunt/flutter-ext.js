// Call a Flutter service extension (ext.flutter.*) via the VM service.
// Usage: node flutter-ext.js <ws-uri> <isolateId> <method> [jsonParams]
const uri = process.argv[2];
const isolateId = process.argv[3];
const method = process.argv[4];
const params = process.argv[5] ? JSON.parse(process.argv[5]) : {};
const ws = new WebSocket(uri);
let nextId = 1;
const pending = new Map();
function rpc(m, p) {
  return new Promise((res, rej) => {
    const id = String(nextId++);
    pending.set(id, { res, rej });
    ws.send(JSON.stringify({ jsonrpc: '2.0', id, method: m, params: p }));
    setTimeout(() => {
      if (pending.has(id)) {
        pending.delete(id);
        rej(new Error('timeout ' + m));
      }
    }, 15000);
  });
}
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    pending.get(m.id).res(m.result !== undefined ? m.result : m.error);
    pending.delete(m.id);
  }
};
async function main() {
  await new Promise((r, j) => {
    ws.onopen = r;
    ws.onerror = () => j(new Error('ws open failed'));
  });
  const vm = await rpc('getVM', {});
  let iso = isolateId;
  if (!iso || iso === 'first') {
    const found = vm.isolates.find((i) => !i.isSystemIsolate);
    iso = found.id;
  }
  const isoDetail = await rpc('getIsolate', { isolateId: iso });
  if (method === 'LIST') {
    console.log(JSON.stringify(isoDetail.extensionRPCs, null, 1));
    process.exit(0);
  }
  const result = await rpc(method, { isolateId: iso, ...params });
  console.log(typeof result === 'string' ? result : JSON.stringify(result));
  process.exit(0);
}
main().catch((e) => {
  console.error('ext exit: ' + e.message);
  process.exit(1);
});
