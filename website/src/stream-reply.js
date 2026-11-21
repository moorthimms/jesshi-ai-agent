export async function streamReply(engine,request,{isCurrent=()=>true,onText=()=>{},onSentence=()=>{},onUsage=()=>{}}={}){
 const chunks=await engine.chat.completions.create({...request,stream:true,stream_options:{include_usage:true}});
 let text='',pending='';
 for await(const chunk of chunks){
  if(!isCurrent())return {text,cancelled:true};
  const delta=chunk.choices?.[0]?.delta?.content||'';
  if(delta){text+=delta;pending+=delta;onText(text);
   let boundary;while((boundary=[...pending.matchAll(/[.!?](?:\s|$)/g)].find(m=>m.index+m[0].length>=12))){const end=boundary.index+boundary[0].length;onSentence(pending.slice(0,end).trim());pending=pending.slice(end);}
  }
  if(chunk.usage)onUsage(chunk.usage);
 }
 if(!isCurrent())return {text,cancelled:true};
 if(pending.trim())onSentence(pending.trim());
 return {text,cancelled:false};
}
