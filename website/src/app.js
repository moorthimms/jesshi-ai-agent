import {streamReply} from './stream-reply.js';
import * as webllm from '@mlc-ai/web-llm';
import * as pdfjs from 'pdfjs-dist';
import {defaults,validateBackup,promptFor} from './core.js';
import {encryptBackup,decryptBackup} from './crypto.js';
pdfjs.GlobalWorkerOptions.workerSrc=new URL('./pdf.worker.mjs',location.href).href;
const $=id=>document.getElementById(id);
// Resolve account identity before reading any user-owned browser records.
let account;
try{
 const response=await fetch('/api/access/me',{cache:'no-store'});
 if(!response.ok)throw Object.assign(Error('Sign in to use Jessy'),{denied:response.status===401||response.status===403});
 account=await response.json();
 if(!['admin','approved'].includes(account.status)||!account.id)throw Object.assign(Error('Access approval required'),{denied:true});
 localStorage.setItem('jessy-last-account',JSON.stringify({id:account.id,owner:account.owner===true}));
}catch(error){
 if(error.denied){location.replace('/');throw error;}
 try{account=JSON.parse(localStorage.getItem('jessy-last-account'));}catch{}
 if(!account?.id){$('engineStatus').textContent='Connect once and sign in before using Jessy offline.';throw Error('No approved offline account');}
}

$('adminLink').hidden=!account.admin;$('adminNav').hidden=!account.admin;
function usage(event){
 if(!navigator.onLine)return;
 fetch('/api/activity',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:crypto.randomUUID(),event}),keepalive:true}).catch(()=>{});
}
usage('app_opened');
let state=defaults(),db,engine,busy=false,loading=false,previous,selected='',generation=0;
const modelIDs=['Qwen2.5-0.5B-Instruct-q4f16_1-MLC','Qwen2.5-1.5B-Instruct-q4f16_1-MLC'];
let selectedModel=localStorage.getItem('jessy-model')||modelIDs[0];
function toast(text){$('toast').textContent=text;$('toast').hidden=false;clearTimeout(toast.timer);toast.timer=setTimeout(()=>$('toast').hidden=true,6500);}
function audit(text){state.activity.unshift(new Date().toLocaleString()+': '+text);state.activity=state.activity.slice(0,200);}
function snapshot(){previous=structuredClone(state);}
function save(){return new Promise((resolve,reject)=>{const tx=db.transaction('data','readwrite');tx.objectStore('data').put(state,'state');tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);});}
async function mutate(fn){snapshot();fn();try{await save();render();}catch(e){toast('Could not save: '+e.message);}}
function el(tag,text,cls){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;}
function button(text,action){const b=el('button',text);b.type='button';b.onclick=()=>Promise.resolve(action()).catch(e=>toast(e.message));return b;}
function tab(name){for(const p of document.querySelectorAll('.page'))p.hidden=p.id!==name;for(const b of document.querySelectorAll('[data-tab]'))b.classList.toggle('active',b.dataset.tab===name);$('pageLabel').textContent=({chat:'YOUR EVERYDAY ASSISTANT',library:'YOUR LOCAL LIBRARY',tasks:'ONE THING AT A TIME',memory:'YOUR PERSONAL SPACE',settings:'YOU’RE IN CONTROL'})[name];}
function renderConversation(){
 $('chatLog').replaceChildren(...state.chats.map(c=>{const d=el('div',undefined,'message '+c.role);d.append(el('strong',c.role==='user'?'You':'Jessy'),el('span',c.content));return d;}));
}
function speakSentence(text){
 if(!state.voice)return;
 const voices=speechSynthesis.getVoices().filter(v=>v.localService);
 if(!voices.length)return;
 const utterance=new SpeechSynthesisUtterance(text);utterance.voice=voices.find(v=>v.lang.startsWith(document.documentElement.lang))||voices[0];speechSynthesis.speak(utterance);
}
function render(){
 document.documentElement.style.fontSize=state.fontSize+'px';
 renderConversation();
 const options=[new Option('General conversation',''),...state.documents.map(d=>new Option(d.name,d.id))];$('source').replaceChildren(...options);$('source').value=selected;
 const search=$('search').value.toLowerCase();$('documents').replaceChildren(...state.documents.filter(d=>(d.name+' '+d.text).toLowerCase().includes(search)).map(d=>{const c=el('article',undefined,'card');c.append(el('h2',d.name),el('p',d.text.slice(0,350)),button('Ask about this',()=>{selected=d.id;render();tab('chat');}),button('Remove',()=>mutate(()=>{state.documents=state.documents.filter(x=>x.id!==d.id);if(selected===d.id)selected='';audit('Removed '+d.name);usage('document_removed');})));return c;}));
 $('taskList').replaceChildren(...state.tasks.map(t=>{const c=el('div',undefined,'card'),label=el('label'),check=el('input');check.type='checkbox';check.checked=t.done;check.onchange=()=>mutate(()=>{t.done=check.checked;usage('task_updated');});label.append(check,document.createTextNode(' '+t.title));c.append(label);if(t.due)c.append(el('p','Reminder: '+new Date(t.due).toLocaleString()));c.append(button('Delete',()=>mutate(()=>{state.tasks=state.tasks.filter(x=>x.id!==t.id);usage('task_deleted');})));return c;}));
 $('routineList').replaceChildren(...state.routines.map(r=>{const c=el('div',undefined,'card');c.append(el('h2',r.name),el('p',r.prompt),button('Review & run',()=>{usage('routine_loaded');tab('chat');$('question').value=r.prompt;$('question').focus();toast('Review the routine instructions, then press Send.');}),button('Delete',()=>mutate(()=>{state.routines=state.routines.filter(x=>x.id!==r.id);})));return c;}));
 $('memoryText').value=state.memory;$('notesText').value=state.notes;$('language').value=state.language;$('lowPower').checked=state.lowPower;$('voice').checked=state.voice;$('fontSize').value=state.fontSize;
 $('activity').textContent=state.activity.join('\n');
}
async function setupModel(){
 if(loading||busy)return;
 if(!navigator.gpu){toast('Local AI requires a browser with WebGPU. Notes, tasks, and documents still work.');return;}
 loading=true;$('loadModel').disabled=true;$('modelStart').disabled=true;
 try{
   if(engine)await engine.unload();engine=undefined;
   const loaded=await webllm.CreateMLCEngine(selectedModel,{initProgressCallback:p=>$('engineStatus').textContent=p.text});
   engine=loaded;$('engineStatus').textContent='Local AI ready · '+selectedModel.split('-Instruct')[0];audit('Local model loaded');usage('model_loaded');await save();
 }catch(e){$('engineStatus').textContent='Model unavailable';toast('Model setup failed: '+e.message);}
 finally{loading=false;$('loadModel').disabled=false;$('modelStart').disabled=false;}
}
async function chat(event){
 event.preventDefault();const question=$('question').value.trim();if(!question||busy)return;if(!engine){toast('Download/load a local model first in Settings.');return;}
 usage('chat_started');const myGeneration=++generation;busy=true;$('send').disabled=true;$('question').value='';
 const doc=state.documents.find(x=>x.id===selected);const messages=[{role:'system',content:promptFor(state,question,doc)},...state.chats.slice(-4).map(c=>({role:c.role,content:c.content.slice(0,2000)})),{role:'user',content:question}];
 const started=performance.now();let firstText;
 speechSynthesis.cancel();
 const pending={role:'assistant',content:''};
 state.chats.push({role:'user',content:question},pending);renderConversation();$('engineStatus').textContent='Thinking on your device…';
 try{
  const result=await streamReply(engine,{messages,max_tokens:state.lowPower?192:(/\b(detailed|long|essay|full code|complete code|story|thorough)\b/i.test(question)?768:256),temperature:.6},{
   isCurrent:()=>myGeneration===generation,
   onText:text=>{
    if(firstText===undefined)firstText=performance.now()-started;
    pending.content=text;const bubble=$('chatLog').lastElementChild?.querySelector('span');if(bubble)bubble.textContent=text;
    $('engineStatus').textContent='Replying locally…';
   },
   onSentence:speakSentence
  });
  if(result.cancelled)return;
  usage('chat_completed');pending.content=result.text||'No answer generated. Try a shorter question.';
  state.chats=state.chats.slice(-100);await save();renderConversation();
 }catch(e){if(myGeneration===generation){usage('chat_failed');if(!pending.content)pending.content='Could not generate a reply. Try again.';renderConversation();await save();toast('Could not answer: '+e.message);}}
 finally{if(myGeneration===generation){busy=false;$('send').disabled=false;$('engineStatus').textContent=firstText===undefined?'Local AI ready':`Local AI ready · first text ${(firstText/1000).toFixed(1)} s`;}}
}

function stop(){usage('generation_stopped');generation++;engine?.interruptGenerate();speechSynthesis.cancel();busy=false;$('send').disabled=false;$('engineStatus').textContent='Stopped';audit('Generation stopped');save().catch(e=>toast(e.message));}
async function importDocument(file){
 if(!file)return;if(file.size>20000000)throw Error('Choose a file smaller than 20 MB');let text='';
 if(file.name.toLowerCase().endsWith('.pdf')){const pdf=await pdfjs.getDocument({data:new Uint8Array(await file.arrayBuffer())}).promise;try{for(let i=1;i<=Math.min(pdf.numPages,100);i++){const page=await pdf.getPage(i);const content=await page.getTextContent();text+=`[Page ${i}]\n`+content.items.map(x=>x.str||'').join(' ')+'\n';if(text.length>=120000)break;}}finally{await pdf.destroy();}}
 else text=await file.text();if(!text.trim())throw Error('No readable text. Scanned PDFs need OCR in the native app.');
 await mutate(()=>{state.documents.push({id:crypto.randomUUID(),name:file.name,text:text.slice(0,120000)});audit('Imported '+file.name);usage('document_imported');});toast('Document saved locally');
}
async function storageInfo(){const v=await navigator.storage?.estimate?.();$('storageInfo').textContent=v?`Browser storage: ${(v.usage/1048576).toFixed(1)} MB used of ${(v.quota/1073741824).toFixed(1)} GB quota.`:'Storage estimates unavailable.';}
let deferredInstall;window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();deferredInstall=e;$('install').hidden=false;});$('install').onclick=async()=>{await deferredInstall?.prompt();deferredInstall=null;$('install').hidden=true;};
for(const b of document.querySelectorAll('[data-tab]'))b.onclick=()=>tab(b.dataset.tab);
for(const b of document.querySelectorAll('[data-prompt]'))b.onclick=()=>{$('question').value=b.dataset.prompt;$('question').focus();};
$('chatForm').onsubmit=chat;$('stop').onclick=stop;$('loadModel').onclick=setupModel;$('modelStart').onclick=setupModel;
$('source').onchange=()=>selected=$('source').value;
$('importDoc').onclick=()=>$('file').click();$('file').onchange=()=>importDocument($('file').files[0]).catch(e=>toast(e.message));$('search').oninput=render;
$('taskForm').onsubmit=e=>{e.preventDefault();const title=$('taskTitle').value.trim();if(!title)return;const due=$('taskDue').value?new Date($('taskDue').value).getTime():undefined;if(due&&due<=Date.now()){toast('Choose a future reminder time.');return;}mutate(()=>{state.tasks.push({id:crypto.randomUUID(),title,done:false,...(due?{due}: {})});audit('Task added');usage('task_added');}).catch(e=>toast(e.message));$('taskTitle').value='';$('taskDue').value='';};
$('routineForm').onsubmit=e=>{e.preventDefault();mutate(()=>state.routines.push({id:crypto.randomUUID(),name:$('routineName').value,prompt:$('routinePrompt').value})).catch(e=>toast(e.message));$('routineForm').reset();usage('routine_saved');};
$('saveNotes').onclick=()=>mutate(()=>{state.memory=$('memoryText').value;state.notes=$('notesText').value;audit('Saved notes and memory');usage('notes_saved');}).then(()=>toast('Saved on this device'));
$('saveSettings').onclick=()=>mutate(()=>{state.language=$('language').value||'English';state.lowPower=$('lowPower').checked;state.voice=$('voice').checked;state.fontSize=Number($('fontSize').value);usage('settings_saved');}).then(()=>toast('Preferences saved'));
$('backup').onclick=async()=>{try{const encrypted=await encryptBackup(state,$('backupPassword').value);const a=el('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(encrypted)],{type:'application/json'}));a.download='Jessy-encrypted-backup.json';a.click();usage('backup_exported');setTimeout(()=>URL.revokeObjectURL(a.href),1000);$('backupPassword').value='';}catch(e){toast(e.message);}};
$('restore').onclick=()=>$('backupFile').click();$('backupFile').onchange=async()=>{try{const file=$('backupFile').files[0];if(!file)return;if(file.size>20000000)throw Error('Backup too large');const restored=validateBackup(await decryptBackup(JSON.parse(await file.text()),$('backupPassword').value));if(!confirm('Replace this browser’s Jessy data with the backup? You can undo this change until the next edit.'))return;await mutate(()=>{state=restored;selected='';audit('Restored backup');usage('backup_restored');});$('backupPassword').value='';toast('Backup restored');}catch(e){toast(e.message);}};
$('undo').onclick=async()=>{if(!previous){toast('No data change to undo');return;}const swap=state;state=previous;previous=swap;selected='';await save();render();toast('Data change undone');usage('data_undone');};
$('requestStorage').onclick=async()=>{const kept=await navigator.storage?.persist?.();toast(kept?'Persistent storage granted. Keep backups too.':'Browser did not grant persistent storage. Keep backups.');};
$('modelSelect').replaceChildren(...modelIDs.map(id=>new Option(id.startsWith('Qwen2.5-0.5')?'Qwen 0.5B · lighter (~0.4 GB download)':'Qwen 1.5B · stronger (~1 GB download)',id)));$('modelSelect').value=selectedModel;
$('modelSelect').onchange=()=>{selectedModel=$('modelSelect').value;localStorage.setItem('jessy-model',selectedModel);$('engineStatus').textContent='Click Download / load to switch model.';};
$('modelDelete').onclick=async()=>{try{if(busy||loading)throw Error('Stop generation and wait for loading first.');if(!confirm('Remove cached files for the selected model? It will require another download.'))return;await engine?.unload();engine=undefined;await webllm.deleteModelAllInfoInCache(selectedModel);$('engineStatus').textContent='Model cache removed';usage('model_cache_removed');await storageInfo();}catch(e){toast(e.message);}};
function connectivity(){$('connection').textContent=navigator.onLine?'Online · inference stays local':'Offline · your space stays here';}addEventListener('online',connectivity);addEventListener('offline',connectivity);connectivity();
$('gpuStatus').textContent=navigator.gpu?'WebGPU is available. Download a model once to enable local chat.':'WebGPU is unavailable in this browser. Local AI cannot run here; other features remain usable.';
try{
 db=await new Promise((resolve,reject)=>{const request=indexedDB.open('jessy-account-'+account.id,1);request.onupgradeneeded=()=>request.result.createObjectStore('data');request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});
 const saved=await new Promise((resolve,reject)=>{const req=db.transaction('data').objectStore('data').get('state');req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});if(saved)state=validateBackup(saved);
 else if(account.owner){
   // Preserve original owner data from the first single-account version.
   const old=await new Promise(resolve=>{const r=indexedDB.open('jessy',1);r.onsuccess=()=>resolve(r.result);r.onerror=()=>resolve(null);});
   if(old?.objectStoreNames.contains('data')){
     const legacy=await new Promise(resolve=>{const r=old.transaction('data').objectStore('data').get('state');r.onsuccess=()=>resolve(r.result);r.onerror=()=>resolve(null);});
     if(legacy){state=validateBackup(legacy);await save();}
   }
   old?.close();
 }
 render();await storageInfo();
}catch(e){toast('Local storage unavailable: '+e.message);}
if('serviceWorker'in navigator)navigator.serviceWorker.register('./sw.js').catch(e=>toast('Offline app setup failed: '+e.message));
setInterval(()=>{for(const t of state.tasks)if(t.due&&!t.done&&!t.notified&&t.due<=Date.now()){t.notified=true;toast('Reminder: '+t.title);audit('Reminder: '+t.title);save().catch(e=>toast(e.message));}},15000);

