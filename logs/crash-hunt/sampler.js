// Dart VM service stack sampler: polls getStack for every non-system
// isolate and prints deduped compact stacks. Usage: node sampler.js <ws-uri>
const uri = process.argv[2];
if (!uri) {
  console.error('usage: node sampler.js ws://127.0.0.1:PORT/TOKEN=/ws');
  process.exit(2);
}
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
    }, 5000);
  });
}
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    pending.get(m.id).res(m.result);
    pending.delete(m.id);
  }
};
let lastLine = '';
function emit(line) {
  if (line === lastLine) return;
  lastLine = line;
  console.log(line);
}
async function main() {
  await new Promise((r, j) => {
    ws.onopen = r;
    ws.onerror = (e) => j(new Error('ws error ' + JSON.stringify(e)));
  });
  emit('sampler connected');
  while (true) {
    const t = new Date().toISOString().slice(11, 23);
    let vm;
    try {
      vm = await rpc('getVM', {});
    } catch (e) {
      emit('[' + t + '] getVM failed: ' + e.message);
      await new Promise((r) => setTimeout(r, 1000));
      continue;
    }
    for (const iso of vm.isolates.filter((i) => !i.isSystemIsolate)) {
      try {
        const st = await rpc('getStack', { isolateId: iso.id });
        const frames = (st.frames || [])
          .slice(0, 16)
          .map((f) => f.function || (f.code && f.code.name) || '?');
        const asyncFrames = (st.asyncCausalFrames || [])
          .slice(0, 16)
          .map((f) => f.function || (f.code && f.code.name) || '?');
        const line =
          '[' + t + '] ' + iso.name + '\n    sync: ' +
          frames.join('  <-  ') +
          (asyncFrames.length ? '\n    async: ' + asyncFrames.join('  <-  ') : '');
        emit(line);
      } catch (e) {
        emit('[' + t + '] ' + iso.name + ' getStack failed: ' + e.message);
      }
    }
    await new Promise((r) => setTimeout(r, 700));
  }
}
main().catch((e) => {
  console.error('sampler exit: ' + e.message);
  process.exit(1);
});
