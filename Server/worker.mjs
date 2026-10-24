import { DurableObject } from 'cloudflare:workers';
import {createRoom, profile, tick, command, snapshot} from './party.mjs';
const now=()=>Date.now()/1000;
const json=(body,status=200)=>Response.json(body,{status,headers:{'Cache-Control':'no-store'}});
const token=()=>crypto.randomUUID()+crypto.randomUUID();
const code=()=>Array.from(crypto.getRandomValues(new Uint8Array(10)),v=>'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[v%32]).join('');
export default {
  async fetch(request,env) {
    const url=new URL(request.url);
    if (url.pathname==='/health') return json({ok:true,version:1});
    const ip=request.headers.get('CF-Connecting-IP') || 'local';
    if (env.RATE_LIMITER && !(await env.RATE_LIMITER.limit({key:ip})).success) return json({error:'Too many requests. Try again shortly.'},429);
    if (request.method==='POST' && url.pathname==='/parties') {
      const id=code();
      return env.PARTIES.getByName(id).fetch(new Request(new URL('/'+id+'/create',request.url),request));
    }
    const match=url.pathname.match(/^\/([A-Z2-9]{10})\/(join|connect)$/);
    if (!match) return json({error:'Party not found'},404);
    return env.PARTIES.getByName(match[1]).fetch(request);
  }
};
export class Party extends DurableObject {
  constructor(ctx,env) {
    super(ctx,env); this.room=null;
    ctx.blockConcurrencyWhile(async()=>{this.room=await ctx.storage.get('room') || null;});
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping','pong'));
  }
  sockets() { return this.ctx.getWebSockets().filter(ws=>ws.readyState===1); }
  send(ws,value) { try {ws.send(JSON.stringify(value));} catch {} }
  broadcast() {
    if (!this.room) return;
    const online=this.sockets().map(ws=>ws.deserializeAttachment()?.id);
    const data=snapshot(this.room,now(),online);
    for (const ws of this.sockets()) this.send(ws,data);
  }
  async save() {
    if (!this.room) return;
    await this.ctx.storage.put('room',this.room);
    const due=Math.min(this.room.expires,this.room.deadline ?? this.room.expires);
    await this.ctx.storage.setAlarm(Math.max(Date.now()+50,due*1000));
  }
  async end() {
    for (const ws of this.sockets()) {this.send(ws,{type:'ended'});ws.close(1000,'Party ended');}
    this.room=null; await this.ctx.storage.deleteAll();
  }
  async fetch(request) {
    try {
      if (this.room && this.room.expires<=now()) await this.end();
      const path=new URL(request.url).pathname.split('/');
      if (path[2]==='connect') {
        if (!this.room) return json({error:'Party has ended'},404);
        if (request.method!=='GET' || request.headers.get('Upgrade')?.toLowerCase()!=='websocket') return json({error:'WebSocket required'},400);
        const bearer=request.headers.get('Authorization')?.replace(/^Bearer /,'');
        const member=this.room.members.find(m=>m.token===bearer);
        if (!member) return json({error:'Invalid membership'},403);
        for (const ws of this.sockets()) if (ws.deserializeAttachment()?.id===member.id) ws.close(1000,'Reconnected');
        const [client,server]=Object.values(new WebSocketPair());
        this.ctx.acceptWebSocket(server);
        server.serializeAttachment({id:member.id,window:Date.now(),count:0});
        tick(this.room,now()); await this.save(); this.broadcast();
        return new Response(null,{status:101,webSocket:client});
      }
      if (request.method!=='POST') return json({error:'POST required'},405);
      const reader=request.body?.getReader();
      if (!reader) return json({error:'Body required'},400);
      let text='',bytes=0; const decoder=new TextDecoder();
      while(true) {
        const part=await reader.read(); if(part.done) break;
        bytes+=part.value.byteLength;
        if(bytes>4096) {await reader.cancel();return json({error:'Request too large'},413);}
        text+=decoder.decode(part.value,{stream:true});
      }
      text+=decoder.decode();
      const data=JSON.parse(text), appearance=profile(data.profile);
      if (path[2]==='create') {
        if (this.room) return json({error:'Please create again'},409);
        this.room=createRoom(path[1],crypto.randomUUID(),data.settings,now());
      }
      if (!this.room) return json({error:'Party not found or expired'},404);
      if (this.room.members.length>=8) return json({error:'Party is full (8 chimps)'},409);
      const member={id:path[2]==='create'?this.room.host:crypto.randomUUID(),token:token(),profile:appearance};
      this.room.members.push(member);this.room.revision++;
      await this.save();this.broadcast();
      return json({code:this.room.code,id:member.id,token:member.token});
    } catch {return json({error:'Invalid party request'},400);}
  }
  async webSocketMessage(ws,raw) {
    const attachment=ws.deserializeAttachment();
    if (!this.room || !attachment) {ws.close(1000,'Party ended');return;}
    if (this.room.expires<=now()) {await this.end();return;}
    try {
      if (typeof raw!=='string' || raw.length>4096) throw Error('Invalid message');
      if (Date.now()-attachment.window>10000) {attachment.window=Date.now();attachment.count=0;}
      if (++attachment.count>30) throw Error('Too many actions. Wait a moment.');
      ws.serializeAttachment(attachment);
      const member=this.room.members.find(m=>m.id===attachment.id);
      if (!member) {ws.close(1008,'Membership ended');return;}
      const message=JSON.parse(raw);
      const transitioned=tick(this.room,now());
      if (message.type==='sync') {
        if (transitioned) {await this.save();this.broadcast();}
        else this.send(ws,snapshot(this.room,now(),this.sockets().map(s=>s.deserializeAttachment()?.id)));
        return;
      }
      if (message.type==='leave') {
        if (member.id===this.room.host) {await this.end();return;}
        this.room.members=this.room.members.filter(m=>m.id!==member.id);
        this.room.revision++; ws.close(1000,'Left party');
      } else if (message.type==='profile') {member.profile=profile(message.profile);this.room.revision++;}
      else if (message.type==='command') command(this.room,member.id,message,now());
      else if (message.type!=='sync') throw Error('Unknown message');
      await this.save();this.broadcast();
    } catch(error) {await this.save();this.send(ws,{type:'error',message:error.message});this.broadcast();}
  }
  async alarm() {
    if (!this.room) return;
    if (this.room.expires<=now()) {await this.end();return;}
    tick(this.room,now());await this.save();this.broadcast();
  }
  async webSocketClose() {this.broadcast();}
  async webSocketError(ws) {ws.close(1011,'Connection error');this.broadcast();}
}
