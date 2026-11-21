import {build} from 'esbuild';
import {mkdir,copyFile,writeFile,readdir,readFile} from 'node:fs/promises';
await mkdir('dist',{recursive:true});
await build({entryPoints:['src/app.js'],bundle:true,external:['url'],format:'esm',outfile:'dist/app.js',minify:true});
await copyFile('node_modules/pdfjs-dist/build/pdf.worker.min.mjs','dist/pdf.worker.mjs');
for(const file of ['index.html','style.css','manifest.webmanifest','icon.svg']) await copyFile('src/'+file,'dist/'+file);
const names=['app.js','pdf.worker.mjs','index.html','style.css','manifest.webmanifest','icon.svg'];
const {createHash}=await import('node:crypto');const hash=createHash('sha256');for(const n of names.sort())hash.update(await readFile('dist/'+n));
const revision=hash.digest('hex').slice(0,12);
await writeFile('dist/sw.js',`const CACHE='jessy-${revision}';const FILES=${JSON.stringify(names.map(n=>'./'+n))};self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(FILES)).then(()=>self.skipWaiting()))});self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k.startsWith('jessy-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});self.addEventListener('fetch',e=>{if(e.request.method!=='GET'||new URL(e.request.url).origin!==self.location.origin)return;e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request)))})`);
// Worker build: membership gates every app asset; only the access landing is public.
const assets={};
const mime={html:'text/html; charset=utf-8',js:'text/javascript',mjs:'text/javascript',css:'text/css',svg:'image/svg+xml',webmanifest:'application/manifest+json'};
for(const name of [...names,'sw.js']) assets[name]={body:await readFile('dist/'+name,'utf8'),type:mime[name.split('.').pop()]||'text/plain'};
await mkdir('dist/server',{recursive:true});
await writeFile('.worker-entry.mjs',`import {createWorker} from './worker/index.js';export default createWorker(${JSON.stringify(assets)});`);
try{await build({entryPoints:['.worker-entry.mjs'],bundle:true,format:'esm',platform:'browser',outfile:'dist/server/index.js',minify:true});}finally{const {unlink}=await import('node:fs/promises');await unlink('.worker-entry.mjs');}
await mkdir('dist/.openai',{recursive:true});
await copyFile('.openai/hosting.json','dist/.openai/hosting.json');
// Only the gated Worker is deployable; leave no duplicate public static app files.
const {unlink}=await import('node:fs/promises');for(const name of [...names,'sw.js'])await unlink('dist/'+name);
