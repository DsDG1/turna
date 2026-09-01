const uri = process.argv[2];
const ws = new WebSocket(uri);
let nextId = 1;
const pending = new Map();
function rpc(method, params, timeoutMs=30000) {
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
  for (const iso of vm.isolates.filter((i) => !i.isSystemIsolate)) {
    try {
      const st = await rpc('getStack', { isolateId: iso.id }, 25000);
      const f = (fr) => (fr || []).map((x) => {
        const fn = x.function?.name ?? x.code?.name ?? '?';
        const loc = x.location ? `@${x.location.script?.uri ?? ''}:${x.location.line ?? '?'}` : '';
        return `${fn} ${loc}`;
      });
      console.log(`===== ${iso.name} (${iso.id}) =====`);
      console.log('--- async causal ---');
      for (const fr of (st.asyncCausalFrames || []).slice(0, 60)) {
        const kind = fr.kind ? `[${fr.kind}]` : '';
        console.log(`  ${kind}${fr.function?.name ?? fr.code?.name ?? '?'}`);
      }
      console.log('--- sync ---');
      console.log('  ' + f(st.frames).slice(0, 30).join('\n  '));
    } catch (e) {
      console.log(`===== ${iso.name} ===== getStack: ${e.message}  <-- THIS isolate is the spinner (never safepoints)`);
    }
  }
  ws.close(); process.exit(0);
}
main().catch((e) => { console.error('exit: ' + e.message); process.exit(1); });
