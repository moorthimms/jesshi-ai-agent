import {USAGE_EVENTS,recordUsage,overview} from './activity.js';
import {notifyAdmin,mailStatus,credentials,exchange,digest,putSetting} from './gmail.js';
export function identity(request){const id=request.headers.get('oai-authenticated-user-id'),email=request.headers.get('oai-authenticated-user-email')?.trim().toLowerCase();return id&&id.length<256&&email&&/^[^\s@<>\r\n]+@[^\s@<>\r\n]+\.[^\s@<>\r\n]+$/.test(email)&&email.length<=254?{id,email}:null;}
export const isAdmin=(user,env)=>!!user&&user.email===env.ADMIN_EMAIL?.trim().toLowerCase();
export const isOwner=(user,env)=>!!user&&user.email===env.OWNER_EMAIL?.trim().toLowerCase();
export function json(data,status=200){return new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'}});}
function fail(message,status){return json({error:message},status);}
export async function membership(user,env){if(!user)return 'anonymous';if(isAdmin(user,env))return 'admin';if(isOwner(user,env))return 'approved';const row=await env.DB.prepare('SELECT status,email FROM jessy_access_requests WHERE user_id=?').bind(user.id).first();return row&&row.email===user.email?row.status:'none';}
async function input(request){const raw=await request.text();if(raw.length>8000)throw Error('Request too large');return JSON.parse(raw);}
export async function accessAPI(request,env){
 const url=new URL(request.url),path=url.pathname,user=identity(request);
 if(!env.DB||!env.ADMIN_EMAIL||!env.SITE_ORIGIN)return fail('Access service is not configured',503);
 if(!user)return fail('Sign in with ChatGPT to continue',401);
 if(request.method!=='GET'&&request.headers.get('Origin')!==url.origin)return fail('Invalid request origin',403);
 if(path==='/api/access/me'&&request.method==='GET')return json({id:user.id,email:user.email,status:await membership(user,env),admin:isAdmin(user,env),owner:isOwner(user,env)});
 if(path==='/api/access/request'&&request.method==='POST'){
  const existing=await env.DB.prepare('SELECT * FROM jessy_access_requests WHERE user_id=?').bind(user.id).first();
  if(isAdmin(user,env)||isOwner(user,env))return json({status:await membership(user,env)});
  if(existing)return json({status:existing.status,notification:existing.notification_status});
  const now=Date.now(),id=crypto.randomUUID();
  const row={id,email:user.email};
  const inserted=await env.DB.prepare('INSERT INTO jessy_access_requests(id,user_id,email,status,created_at,updated_at,notification_status) VALUES(?,?,?,\'pending\',?,?,\'not_sent\') ON CONFLICT(user_id) DO NOTHING').bind(id,user.id,user.email,now,now).run();
  if(!inserted.meta.changes)return json({status:'pending',notification:'already_requested'});
  const notification=await notifyAdmin(env,row);
  await env.DB.prepare('UPDATE jessy_access_requests SET notification_status=? WHERE id=?').bind(notification,id).run();
  return json({status:'pending',notification});
 }
 if(path==='/api/activity'&&request.method==='POST'){
  const status=await membership(user,env);
  if(!['admin','approved'].includes(status))return fail('Approved access required',403);
  const data=await input(request);
  if(!USAGE_EVENTS.has(data.event)||typeof data.id!=='string'||!/^[a-zA-Z0-9-]{16,64}$/.test(data.id)||Object.keys(data).some(k=>!['id','event'].includes(k)))return fail('Invalid activity event',400);
  const accepted=await recordUsage(env,user,data.event,data.id);return accepted?json({ok:true}):fail('Activity limit reached',429);
 }
 if(!path.startsWith('/api/admin/'))return fail('Not found',404);
 if(!isAdmin(user,env))return fail('Administrator access required',403);
 if(path==='/api/admin/overview'&&request.method==='GET')return json(await overview(env));
 if(path==='/api/admin/requests'&&request.method==='GET'){
  const rows=await env.DB.prepare('SELECT id,email,status,created_at,updated_at,notification_status FROM jessy_access_requests ORDER BY CASE status WHEN \'pending\' THEN 0 ELSE 1 END,created_at DESC LIMIT 200').all();
  const requested=url.searchParams.get('request');
  if(requested&&requested.length<=100&&!rows.results.some(r=>r.id===requested)){
   const pinned=await env.DB.prepare('SELECT id,email,status,created_at,updated_at,notification_status FROM jessy_access_requests WHERE id=?').bind(requested).first();
   if(pinned)rows.results.unshift(pinned);
  }
  return json({requests:rows.results,mail:await mailStatus(env),adminEmail:env.ADMIN_EMAIL});
 }
 if(path==='/api/admin/decision'&&request.method==='POST'){
  const data=await input(request);if(typeof data.id!=='string'||data.id.length>100||!['approved','denied'].includes(data.status))return fail('Invalid decision',400);
  const row=await env.DB.prepare('SELECT * FROM jessy_access_requests WHERE id=?').bind(data.id).first();if(!row)return fail('Request not found',404);
  const now=Date.now();await env.DB.batch([
   env.DB.prepare('UPDATE jessy_access_requests SET status=?,decided_by=?,updated_at=? WHERE id=?').bind(data.status,user.id,now,data.id),
   env.DB.prepare('INSERT INTO jessy_access_audit(id,request_id,actor,action,created_at) VALUES(?,?,?,?,?)').bind(crypto.randomUUID(),data.id,user.id,data.status,now)
  ]);return json({status:data.status});
 }
 if(path==='/api/admin/notify'&&request.method==='POST'){
  const data=await input(request);if(typeof data.id!=='string'||data.id.length>100)return fail('Invalid request',400);
  const row=await env.DB.prepare('SELECT * FROM jessy_access_requests WHERE id=?').bind(data.id).first();if(!row)return fail('Request not found',404);
  const notification=await notifyAdmin(env,row);await env.DB.prepare('UPDATE jessy_access_requests SET notification_status=? WHERE id=?').bind(notification,row.id).run();return json({notification});
 }
 if(path==='/api/admin/gmail/client'&&request.method==='POST'){
  const data=await input(request);
  if(typeof data.id!=='string'||!data.id.endsWith('.apps.googleusercontent.com')||typeof data.secret!=='string'||data.secret.length<10||data.secret.length>2000)return fail('Enter a valid Google web OAuth client ID and secret',400);
  await putSetting(env,'client',JSON.stringify({id:data.id,secret:data.secret}));
  await env.DB.prepare('DELETE FROM jessy_mail_settings WHERE id=\'refresh\'').run();return json({status:'authorization_required'});
 }
 if(path==='/api/admin/gmail/connect'&&request.method==='POST'){
  let client;try{client=await credentials(env);}catch{return fail('Save the Google OAuth client ID and client secret before authorizing Gmail.',400);}
  const state=crypto.randomUUID()+crypto.randomUUID(),hash=await digest(state),now=Date.now();
  await env.DB.prepare('DELETE FROM jessy_oauth_states WHERE expires_at<?').bind(now).run();
  await env.DB.prepare('INSERT INTO jessy_oauth_states(state_hash,user_id,expires_at) VALUES(?,?,?)').bind(hash,user.id,now+600000).run();
  const redirect=new URL('/api/admin/gmail/callback',env.SITE_ORIGIN).href;
  const auth=new URL('https://accounts.google.com/o/oauth2/v2/auth');auth.search=new URLSearchParams({client_id:client.id,redirect_uri:redirect,response_type:'code',scope:'https://www.googleapis.com/auth/gmail.send',access_type:'offline',prompt:'consent',state,login_hint:env.ADMIN_EMAIL}).toString();return json({url:auth.href});
 }
 if(path==='/api/admin/gmail/callback'&&request.method==='GET'){
  const state=url.searchParams.get('state'),code=url.searchParams.get('code');if(!state||!code||state.length>256||code.length>4096)return fail('Gmail authorization was cancelled or invalid',400);
  const hash=await digest(state);const stored=await env.DB.prepare('DELETE FROM jessy_oauth_states WHERE state_hash=? AND user_id=? AND expires_at>? RETURNING state_hash').bind(hash,user.id,Date.now()).first();if(!stored)return fail('Authorization expired. Start again from the admin page.',400);
  const tokens=await exchange(env,{code,grant_type:'authorization_code',redirect_uri:new URL('/api/admin/gmail/callback',env.SITE_ORIGIN).href});if(!tokens.refresh_token||!tokens.scope?.split(' ').includes('https://www.googleapis.com/auth/gmail.send'))return fail('Google did not grant persistent Gmail sending access. Reconnect.',400);
  await putSetting(env,'refresh',tokens.refresh_token);return Response.redirect(new URL('/admin?gmail=connected',env.SITE_ORIGIN),303);
 }
 if(path==='/api/admin/gmail/disconnect'&&request.method==='POST'){
  await env.DB.prepare('DELETE FROM jessy_mail_settings WHERE id IN (\'refresh\',\'client\')').run();return json({status:'disconnected'});
 }
 return fail('Not found',404);
}
