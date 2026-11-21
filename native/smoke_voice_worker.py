"""Test bundled wake recognition with synthesized audio, without opening a microphone."""
import json
from pathlib import Path
import subprocess
import tempfile
import os
import wave
resources=Path(__file__).resolve().parents[1]/'dist/Offline Assistant.app/Contents/Resources'
p=subprocess.Popen([str(resources/'backend/backend'),str(resources),'--voice-only'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env={**os.environ,'HF_HUB_OFFLINE':'1'})
def read():
 line=p.stdout.readline()
 if not line:raise RuntimeError(p.stderr.read())
 result=json.loads(line);print(result,flush=True)
 assert result['type'] not in ('error','voice_error'),result
 return result
try:
 assert read()['type']=='voice_ready'
 with tempfile.TemporaryDirectory() as folder:
  aiff=Path(folder)/'speech.aiff';wav=Path(folder)/'jessy-listen-test.wav'
  subprocess.run(['/usr/bin/say','-o',str(aiff),'Hi Jessie. What time is it?'],check=True)
  subprocess.run(['/usr/bin/afconvert','-f','WAVE','-d','LEI16@16000','-c','1',str(aiff),str(wav)],check=True)
  p.stdin.write(json.dumps({'type':'chunk','path':str(wav),'generation':'test'})+'\n');p.stdin.flush()
  result=read();assert result['type']=='voice_result' and result['wake'] is True,result
  assert 'time' in result['text'].lower(),result
  assert not wav.exists(),'Temporary audio must be deleted'
  with wave.open(str(wav),'wb') as out:
   out.setparams((1,2,16000,0,'NONE','not compressed'));out.writeframes(bytes(16000*2*2))
  p.stdin.write(json.dumps({'type':'chunk','path':str(wav),'generation':'test'})+'\n');p.stdin.flush()
  endpoint=read();assert endpoint.get('has_speech') is True and endpoint['trailing_silence'] >= 1,endpoint
  with wave.open(str(wav),'wb') as out:
   out.setparams((1,2,16000,0,'NONE','not compressed'));out.writeframes(bytes(1600*2))
  p.stdin.write(json.dumps({'type':'finish','path':str(wav),'generation':'test'})+'\n');p.stdin.flush()
  final=read();assert final['type']=='voice_final' and 'time' in final['text'].lower(),final
 p.stdin.write('{"type":"quit"}\n');p.stdin.flush();p.wait(timeout=15);assert p.returncode==0
 print('Bundled local wake recognition and cleanup passed')
finally:
 if p.poll() is None:p.terminate();p.wait(timeout=15)
