export const defaults = { focusMinutes:25, shortBreakMinutes:5, longBreakMinutes:15, longBreakInterval:4, autoStartBreaks:false, autoStartFocus:false };
const bounds = {focusMinutes:[1,180],shortBreakMinutes:[1,60],longBreakMinutes:[1,120],longBreakInterval:[1,12]};
export function settings(input = {}) {
  const result = {...defaults};
  for (const [key,[low,high]] of Object.entries(bounds)) {
    if (input[key] !== undefined && (!Number.isInteger(input[key]) || input[key]<low || input[key]>high)) throw Error('Invalid timer settings');
    result[key] = input[key] ?? result[key];
  }
  for (const key of ['autoStartBreaks','autoStartFocus']) result[key] = input[key] === true;
  return result;
}
export function profile(input = {}) {
  const name = typeof input.name === 'string' ? input.name.trim().slice(0,24).replace(/[\x00-\x1f\x7f]/g,'') : '';
  if (!name) throw Error('Enter a name');
  return { name, color: ['ink','sage','blue','rose','gold'].includes(input.color) ? input.color : 'ink', accessory: ['none','glasses','crown','bow'].includes(input.accessory) ? input.accessory : 'none' };
}
export function duration(room,phase) { return room.settings[phase === 'focus' ? 'focusMinutes' : phase === 'shortBreak' ? 'shortBreakMinutes' : 'longBreakMinutes']*60; }
export function prepare(room,phase) { room.phase=phase; room.duration=duration(room,phase); room.remaining=room.duration; room.deadline=null; room.started=false; }
export function createRoom(code,host,config,now) {
  const room={code,host,settings:settings(config),revision:1,cycle:0,completion:null,expires:now+86400,members:[]};
  prepare(room,'focus'); return room;
}
export function tick(room,now) {
  if (room.deadline === null || now<room.deadline) return false;
  const phase=room.phase, at=room.deadline;
  if (phase==='focus') room.cycle=Math.min(room.settings.longBreakInterval,room.cycle+1);
  else if (phase==='longBreak') room.cycle=0;
  const next=phase==='focus' ? (room.cycle>=room.settings.longBreakInterval ? 'longBreak':'shortBreak'):'focus';
  prepare(room,next);
  if (next==='focus' ? room.settings.autoStartFocus : room.settings.autoStartBreaks) { room.deadline=now+room.duration; room.started=true; }
  room.revision++;
  room.completion={id:room.revision,phase,at};
  return true;
}
export function command(room,member,message,now) {
  if (member!==room.host) throw Error('Only the host controls the party timer');
  // Reconcile before checking revision so commands at a deadline cannot skip two phases.
  tick(room,now);
  if (message.revision!==room.revision) throw Error('Timer changed. Try again.');
  switch (message.action) {
    case 'start': if (room.deadline===null) {room.deadline=now+room.remaining;room.started=true;} break;
    case 'pause': if (room.deadline!==null) {room.remaining=Math.max(0,room.deadline-now);room.deadline=null;} break;
    case 'reset': prepare(room,room.phase); break;
    case 'skip': {
      const previous=room.phase;
      if (previous==='longBreak') room.cycle=0;
      prepare(room,previous==='focus'?'shortBreak':'focus'); break;
    }
    case 'select':
      if (!['focus','shortBreak','longBreak'].includes(message.phase)) throw Error('Invalid phase');
      if (room.phase==='longBreak' && message.phase!=='longBreak') room.cycle=0;
      prepare(room,message.phase); break;
    default: throw Error('Unknown timer action');
  }
  room.revision++;
}
export function snapshot(room,now,online=[]) {
  return {type:'state',code:room.code,host:room.host,revision:room.revision,settings:room.settings,phase:room.phase,duration:room.duration,remaining:room.remaining,deadline:room.deadline,started:room.started,cycle:room.cycle,completion:room.completion,serverTime:now,expires:room.expires,members:room.members.map(({id,profile})=>({id,profile,online:online.includes(id)}))};
}
