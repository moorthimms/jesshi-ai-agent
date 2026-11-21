const encode=b=>btoa(String.fromCharCode(...new Uint8Array(b)));
const decode=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
async function keyFor(password,salt){
 if(password.length<12)throw Error('Use a backup password with at least 12 characters.');
 const material=await crypto.subtle.importKey('raw',new TextEncoder().encode(password),'PBKDF2',false,['deriveKey']);
 return crypto.subtle.deriveKey({name:'PBKDF2',salt,iterations:250000,hash:'SHA-256'},material,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
}
export async function encryptBackup(value,password){
 const salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));
 const key=await keyFor(password,salt);
 const bytes=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,new TextEncoder().encode(JSON.stringify(value)));
 // Chunk encoding avoids stack overflow for document backups.
 let binary='';const data=new Uint8Array(bytes);for(let i=0;i<data.length;i+=8192)binary+=String.fromCharCode(...data.subarray(i,i+8192));
 return {format:'jessy-encrypted-v1',salt:encode(salt),iv:encode(iv),data:btoa(binary)};
}
export async function decryptBackup(value,password){
 if(value?.format!=='jessy-encrypted-v1'||typeof value.data!=='string')throw Error('Invalid encrypted backup');
 const salt=decode(value.salt),iv=decode(value.iv);if(salt.length!==16||iv.length!==12)throw Error('Invalid backup parameters');
 const key=await keyFor(password,salt);let clear;
 try{clear=await crypto.subtle.decrypt({name:'AES-GCM',iv},key,decode(value.data));}catch{throw Error('Incorrect password or damaged backup');}
 return JSON.parse(new TextDecoder().decode(clear));
}
