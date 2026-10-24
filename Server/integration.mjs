import assert from 'node:assert/strict';
import WebSocket from 'ws';
const base=process.env.PARTY_TEST_URL || 'http://127.0.0.1:8787';
async function post(path,body) {const r=await fetch(base+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});assert.equal(r.status,200,await r.clone().text());return r.json()}
function connect(member) {
 const ws=new WebSocket(base.replace(/^http/,'ws')+'/'+member.code+'/connect',{headers:{Authorization:'Bearer '+member.token}});
 const messages=[];ws.on('message',bytes=>messages.push(JSON.parse(bytes)));ws.on('error',()=>{});
 return {ws,messages,send:message=>ws.send(JSON.stringify(message)),async wait(predicate,timeout=8000){const end=Date.now()+timeout;while(Date.now()<end){const found=messages.find(predicate);if(found)return found;await new Promise(r=>setTimeout(r,20))}throw Error('Timed out waiting for state')}};
}
const host=await post('/parties',{profile:{name:'Host',color:'sage',accessory:'glasses'},settings:{focusMinutes:1}});
const a=connect(host);let s=await a.wait(s=>s.type==='state');assert.equal(s.phase,'focus');
const guest=await post('/'+host.code+'/join',{profile:{name:'Guest',color:'blue',accessory:'crown'}});
const b=connect(guest);s=await b.wait(s=>s.type==='state'&&s.members.length===2);assert.equal(s.members[1].profile.accessory,'crown');
a.send({type:'command',action:'start',revision:s.revision});
const started=await a.wait(s=>s.type==='state'&&s.deadline!=null);const synced=await b.wait(s=>s.type==='state'&&s.deadline!=null);assert.equal(started.deadline,synced.deadline);
b.send({type:'command',action:'pause',revision:synced.revision});await b.wait(s=>s.type==='error'&&s.message.includes('host'));
a.send({type:'command',action:'pause',revision:started.revision});const paused=await b.wait(s=>s.type==='state'&&s.deadline===null&&s.started);assert.ok(paused.remaining<=60);
a.send({type:'command',action:'start',revision:started.revision});await a.wait(s=>s.type==='error'&&s.message.includes('changed'));
b.send({type:'profile',profile:{name:'Updated',color:'rose',accessory:'bow'}});const changed=await a.wait(s=>s.type==='state'&&s.members.some(m=>m.profile.name==='Updated'));assert.ok(!JSON.stringify(changed).includes(guest.token));
b.ws.close();const reconnected=connect(guest);const recovered=await reconnected.wait(s=>s.type==='state'&&s.members.length===2);assert.equal(recovered.deadline,null);assert.equal(recovered.remaining,paused.remaining);
if (!process.env.SKIP_ALARM) {
a.send({type:'command',action:'start',revision:recovered.revision});
const completion=await a.wait(s=>s.type==='state'&&s.completion!=null,70000);
const guestCompletion=await reconnected.wait(s=>s.type==='state'&&s.completion!=null);
assert.equal(completion.completion.id,guestCompletion.completion.id);assert.equal(completion.phase,'shortBreak');assert.equal(completion.deadline,null);
}
a.send({type:'leave'});await reconnected.wait(s=>s.type==='ended');a.ws.close();reconnected.ws.close();
console.log('PASS: two-client sync, host authority, stale commands, customization, token privacy, reconnect and host end' + (process.env.SKIP_ALARM ? '.' : ', and real deadline alarm.'));
b.ws.terminate();
