export const USAGE_EVENTS=new Set(['app_opened','chat_started','chat_completed','chat_failed','generation_stopped','document_imported','document_removed','task_added','routine_saved','routine_loaded','backup_exported','backup_restored','model_loaded','task_updated','task_deleted','notes_saved','settings_saved','data_undone','model_cache_removed']);
export async function recordUsage(env,user,event,id){
 const now=Date.now();
 const count=await env.DB.prepare('SELECT count(*) AS n FROM jessy_usage_events WHERE user_id=? AND created_at>?').bind(user.id,now-3600000).first();
 if(count.n>=120)return false;
 await env.DB.prepare('INSERT INTO jessy_usage_events(id,user_id,email,event,created_at) VALUES(?,?,?,?,?) ON CONFLICT(id) DO NOTHING').bind(id,user.id,user.email,event,now).run();
 return true;
}
export async function overview(env){
 const [totals,visitors,activity,decisions,requests]=await Promise.all([
 env.DB.prepare('SELECT status,count(*) AS count FROM jessy_access_requests GROUP BY status').all(),
 env.DB.prepare('SELECT count(DISTINCT user_id) AS count FROM jessy_usage_events WHERE created_at>?').bind(Date.now()-86400000).first(),
 env.DB.prepare('SELECT id,email,event,created_at FROM jessy_usage_events ORDER BY created_at DESC LIMIT 200').all(),
 env.DB.prepare('SELECT a.id,r.email,a.actor,a.action,a.created_at FROM jessy_access_audit a LEFT JOIN jessy_access_requests r ON r.id=a.request_id ORDER BY a.created_at DESC LIMIT 200').all(),
 env.DB.prepare("SELECT id,email,'access_requested' AS event,created_at FROM jessy_access_requests ORDER BY created_at DESC LIMIT 200").all()
 ]);
 return {counts:Object.fromEntries(totals.results.map(x=>[x.status,x.count])),activeAccounts24h:visitors.count,
 activity:[...activity.results,...requests.results,...decisions.results.map(x=>({...x,event:x.action==='approved'?'access_approved':'access_denied'}))].sort((a,b)=>b.created_at-a.created_at).slice(0,200),decisions:decisions.results,retention:'Recent 200 usage events and 200 access decisions; usage is client-reported and excludes private content.'};
}
