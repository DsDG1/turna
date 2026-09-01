
const uri = process.argv[2];
const ws = new WebSocket(uri);
let nextId = 1; const pending = new Map();
function rpc(method, params) { return new Promise((res, rej) => { const id = String(nextId++); pending.set(id, {res, rej}); ws.send(JSON.stringify({jsonrpc:'2.0',id,method,params})); setTimeout(()=>{if(pending.has(id)){pending.delete(id);rej(new Error('timeout'));}},60000); }); }
ws.onmessage = (ev) => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { m.error ? pending.get(m.id).rej(new Error(m.error.message)) : pending.get(m.id).res(m.result); pending.delete(m.id); } };
async function main() {
  await new Promise((r,j)=>{ws.onopen=r;ws.onerror=()=>j(new Error('ws'));});
  const vm = await rpc('getVM', {});
  const main = vm.isolates.find((i)=>i.name==='main');
  const prof = await rpc('getAllocationProfile', { isolateId: main.id });
  console.log(JSON.stringify(prof));
  ws.close(); process.exit(0);
}
main().catch((e)=>{console.error('exit: '+e.message);process.exit(1);});
