const uri = process.argv[2];
const ws = new WebSocket(uri);
let nextId = 1; const pending = new Map();
function rpc(method, params) { return new Promise((res, rej) => { const id = String(nextId++); pending.set(id, {res, rej}); ws.send(JSON.stringify({jsonrpc:'2.0',id,method,params})); setTimeout(()=>{if(pending.has(id)){pending.delete(id);rej(new Error('timeout'));}},20000); }); }
ws.onmessage = (ev) => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { m.error ? pending.get(m.id).rej(new Error(m.error.message)) : pending.get(m.id).res(m.result); pending.delete(m.id); } };
const fs = require('fs');
async function main() {
  await new Promise((r,j)=>{ws.onopen=r;ws.onerror=()=>j(new Error('ws'));});
  console.log('stackloop connected');
  let n = 0;
  while (true) {
    const t = new Date().toISOString().slice(11,23);
    try {
      const vm = await rpc('getVM', {});
      const main = vm.isolates.find((i)=>i.name==='main');
      const st = await rpc('getStack', { isolateId: main.id });
      const frames = (st.frames||[]).map(f=>`${f.function?.name ?? '?'}@${f.location ? (f.location.line ?? '?') : '?'}`);
      const asyncF = (st.asyncCausalFrames||[]).map(f=>`${f.kind? '['+f.kind+']' : ''}${f.function?.name ?? f.code?.name ?? '?'}`);
      const line = `[${t}] sync: ${frames.slice(0,10).join(' <- ')}`;
      console.log(line);
      fs.appendFileSync('stackloop.log', `[${t}]\nSYNC:\n${frames.map(f=>'  '+f).join('\n')}\nASYNC:\n${asyncF.map(f=>'  '+f).join('\n')}\n---\n`);
      n++;
    } catch (e) {
      console.log(`[${t}] ${e.message}`);
    }
    await new Promise((r)=>setTimeout(r,1000));
  }
}
main().catch((e)=>{console.error('exit: '+e.message);process.exit(1);});
