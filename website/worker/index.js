import {identity,isAdmin,membership,accessAPI,json} from './access.js';
import {landing,adminPage} from './pages.js';
export function createWorker(assets){return {async fetch(request,env){
 const url=new URL(request.url),user=identity(request);
 try{
  if(url.pathname.startsWith('/api/'))return await accessAPI(request,env);
  if(!['GET','HEAD'].includes(request.method))return new Response('Method not allowed',{status:405});
  const headers={'Content-Type':'text/html; charset=utf-8','Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'same-origin'};
  if(!env.DB||!env.ADMIN_EMAIL||!env.SITE_ORIGIN)return new Response('Access service is not configured. Contact the site owner.',{status:503,headers});
  if(url.pathname==='/admin'){
   if(!user)return Response.redirect(new URL('/signin-with-chatgpt?return_to=%2Fadmin',url),302);
   if(!isAdmin(user,env))return new Response('Sign in with the configured access administrator account.',{status:403,headers});
   return new Response(request.method==='HEAD'?null:adminPage(env.ADMIN_EMAIL,new URL(env.SITE_ORIGIN).origin),{headers});
  }
  const status=await membership(user,env),allowed=['admin','approved'].includes(status);
  if(url.pathname==='/'){
   if(allowed)return Response.redirect(new URL(status==='admin'?'/admin':'/app/',url),302);
   return new Response(request.method==='HEAD'?null:landing(user,status),{headers});
  }
  if(url.pathname.startsWith('/app/')){
   if(!allowed)return Response.redirect(new URL('/',url),302);
   const name=url.pathname.slice(5)||'index.html',asset=assets[name];
   if(!asset)return new Response('Not found',{status:404});
   return new Response(request.method==='HEAD'?null:asset.body,{headers:{'Content-Type':asset.type,'Cache-Control':'private, no-cache','X-Content-Type-Options':'nosniff',...(name==='sw.js'?{'Service-Worker-Allowed':'/app/'}:{})}});
  }
  // Replace the old root-scoped service worker so prior app caches do not mask the access landing page.
  if(url.pathname==='/sw.js')return new Response("self.addEventListener('install',()=>self.skipWaiting());self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('jessy-')).map(k=>caches.delete(k)))).then(()=>self.registration.unregister()).then(()=>self.clients.claim())));",{headers:{'Content-Type':'text/javascript','Cache-Control':'no-store'}});
  return new Response('Not found',{status:404});
 }catch(error){console.error('Jessy access service failed',error?.name||'Error');return json({error:'Access service is temporarily unavailable. Try again later.'},503);}
}};}
