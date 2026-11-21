const encoder=new TextEncoder();
const b64=bytes=>{let s='';for(const x of bytes)s+=String.fromCharCode(x);return btoa(s);};
const unb64=s=>Uint8Array.from(atob(s),x=>x.charCodeAt(0));
export const base64url=bytes=>b64(bytes).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
export async function digest(value){return base64url(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(value))));}
async function masterKey(env){if(!env.GMAIL_TOKEN_KEY)throw Error('Mail encryption key is not configured');const bytes=unb64(env.GMAIL_TOKEN_KEY);if(bytes.length!==32)throw Error('Invalid mail encryption key');return crypto.subtle.importKey('raw',bytes,'AES-GCM',false,['encrypt','decrypt']);}
export async function seal(value,env){const iv=crypto.getRandomValues(new Uint8Array(12));const data=await crypto.subtle.encrypt({name:'AES-GCM',iv},await masterKey(env),encoder.encode(value));return JSON.stringify({iv:b64(iv),data:b64(new Uint8Array(data))});}
export async function open(value,env){const box=JSON.parse(value);const clear=await crypto.subtle.decrypt({name:'AES-GCM',iv:unb64(box.iv)},await masterKey(env),unb64(box.data));return new TextDecoder().decode(clear);}
export async function setting(env,id){const row=await env.DB.prepare('SELECT value FROM jessy_mail_settings WHERE id=?').bind(id).first();return row?open(row.value,env):null;}
export async function putSetting(env,id,value){const sealed=await seal(value,env);await env.DB.prepare('INSERT INTO jessy_mail_settings(id,value,updated_at) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at').bind(id,sealed,Date.now()).run();}
export async function mailStatus(env){if(!env.GMAIL_TOKEN_KEY)return 'not_configured';const [client,refresh]=await Promise.all([setting(env,'client'),setting(env,'refresh')]);return refresh&&client?'connected':client?'authorization_required':'not_configured';}
export async function credentials(env){const value=await setting(env,'client');if(!value)throw Error('Save your Google OAuth client first');return JSON.parse(value);}
export async function exchange(env,body){const client=await credentials(env);const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({...body,client_id:client.id,client_secret:client.secret}),signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('Google authorization failed. Reconnect Gmail.');return response.json();}
export async function notifyAdmin(env,row){
 if(await mailStatus(env)!=='connected')return 'not_configured';
 try{
  const refreshed=await exchange(env,{grant_type:'refresh_token',refresh_token:await setting(env,'refresh')});
  if(!refreshed.access_token)throw Error('No token');
  const origin=new URL(env.SITE_ORIGIN).origin;
  const text=`Someone requested access to Jessy.\r\n\r\nAccount: ${row.email}\r\n\r\nReview and approve or reject: ${origin}/admin?request=${encodeURIComponent(row.id)}\r\n\r\nSign in as ${env.ADMIN_EMAIL} to decide. Opening this link alone does not grant access.\r\n`;
  const mime=`To: ${env.ADMIN_EMAIL}\r\nSubject: Jessy access request\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n${b64(encoder.encode(text))}`;
  const response=await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send',{method:'POST',headers:{Authorization:'Bearer '+refreshed.access_token,'Content-Type':'application/json'},body:JSON.stringify({raw:base64url(encoder.encode(mime))}),signal:AbortSignal.timeout(15000)});
  return response.ok?'sent':'failed';
 }catch{return 'failed';}
}
