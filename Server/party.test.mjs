import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRoom,profile,settings,tick,command,snapshot} from './party.mjs';
const room=()=>createRoom('ABCDEFGHIJ','host',{},1000);
test('server deadlines, pause, resume and completion',()=>{
 const r=room();command(r,'host',{action:'start',revision:r.revision},1000);assert.equal(r.deadline,2500);
 command(r,'host',{action:'pause',revision:r.revision},1100);assert.equal(r.remaining,1400);assert.equal(r.deadline,null);
 command(r,'host',{action:'start',revision:r.revision},1200);assert.equal(r.deadline,2600);
 assert.equal(tick(r,2599),false);assert.equal(tick(r,2600),true);assert.equal(r.phase,'shortBreak');assert.equal(r.cycle,1);assert.equal(r.deadline,null);assert.equal(tick(r,9000),false);
});
test('guest cannot mutate timer',()=>{const r=room();assert.throws(()=>command(r,'guest',{action:'start',revision:1},1000),/host/);assert.equal(r.deadline,null)});
test('stale and simultaneous commands rejected',()=>{const r=room();command(r,'host',{action:'start',revision:1},1000);assert.throws(()=>command(r,'host',{action:'pause',revision:1},1100),/changed/);assert.equal(r.deadline,2500)});
test('deadline race does not skip the successor',()=>{const r=room();command(r,'host',{action:'start',revision:1},1000);assert.throws(()=>command(r,'host',{action:'skip',revision:r.revision},2500),/changed/);assert.equal(r.phase,'shortBreak');assert.equal(r.cycle,1)});
test('four completed focuses lead to long break',()=>{const r=room();let time=1000;for(let i=0;i<4;i++){command(r,'host',{action:'start',revision:r.revision},time);time=r.deadline;tick(r,time);assert.equal(r.phase,i===3?'longBreak':'shortBreak');if(i<3)command(r,'host',{action:'skip',revision:r.revision},time)}command(r,'host',{action:'skip',revision:r.revision},time);assert.equal(r.cycle,0)});
test('skipped and reset focus gives no credit',()=>{const r=room();command(r,'host',{action:'start',revision:1},1000);command(r,'host',{action:'reset',revision:r.revision},1200);assert.equal(r.cycle,0);assert.equal(r.remaining,1500);command(r,'host',{action:'skip',revision:r.revision},1200);assert.equal(r.cycle,0)});
test('late alarm transitions once, autostart begins at observed time',()=>{const r=createRoom('ABCDEFGHIJ','host',{autoStartBreaks:true},1000);command(r,'host',{action:'start',revision:1},1000);tick(r,10000);assert.equal(r.phase,'shortBreak');assert.equal(r.deadline,10300);assert.equal(r.cycle,1)});
test('snapshot never leaks member credentials',()=>{const r=room();r.members=[{id:'a',token:'secret',profile:profile({name:'A'})}];const s=snapshot(r,1000,['a']);assert.equal(s.members[0].online,true);assert.ok(!JSON.stringify(s).includes('secret'));assert.equal(s.serverTime,1000)});
test('invalid durations, accessories, names and actions',()=>{assert.throws(()=>settings({focusMinutes:0}));assert.throws(()=>settings({focusMinutes:1.5}));assert.throws(()=>profile({name:'  '}));assert.equal(profile({name:'A',accessory:'script'}).accessory,'none');assert.equal(profile({name:'A'.repeat(100)}).name.length,24);const r=room();assert.throws(()=>command(r,'host',{action:'select',phase:'evil',revision:1},1000));});
test('persisted state remains authoritative across reload',()=>{const r=room();command(r,'host',{action:'start',revision:1},1000);const restored=JSON.parse(JSON.stringify(r));tick(restored,2500);assert.equal(restored.cycle,1);assert.equal(restored.completion.at,2500);assert.equal(restored.phase,'shortBreak')});
