"""Exercise only bundled executables/assets, with a minimal environment."""
import json
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

resources = (Path(sys.argv[1]).resolve() / 'Contents/Resources') if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'dist/Offline Assistant.app/Contents/Resources'
env = {'PATH': '/usr/bin:/bin', 'HOME': str(Path.home()), 'HF_HUB_OFFLINE': '1'}
p = subprocess.Popen([str(resources/'backend/backend'), str(resources)], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd='/tmp', env=env)
def read():
    line = p.stdout.readline()
    if not line:
        raise RuntimeError(p.stderr.read())
    obj = json.loads(line)
    print(obj, flush=True)
    assert obj['type'] != 'error', obj
    return obj

def result():
    obj = read()
    while obj['type'] in ('activity', 'answer_start', 'delta', 'speech', 'timing'):
        obj = read()
    return obj

def send(obj):
    p.stdin.write(json.dumps(obj)+'\n'); p.stdin.flush()
try:
    assert read()['type'] == 'ready'
    send({'type': 'chat', 'text': 'Use get_time and tell me the current local time. Do not use other tools.', 'allowed': ['get_time']})
    assert result()['type'] == 'answer'
    send({'type': 'chat', 'text': 'Open Calculator using open_app.', 'allowed': ['open_app']})
    assert result()['type'] == 'confirm'
    send({'approved': False})
    assert result()['type'] == 'answer'
    send({'type': 'reset'})
    assert result()['type'] == 'reset'
    send({'type': 'chat', 'text': 'What is the project codename? Cite the source.',
          'context': '[Page 3] The project codename is BLUEFIN.', 'source': 'test.txt',
          'allowed': ['open_app'], 'low_power': True})
    answer = result()
    assert answer['type'] == 'answer' and 'BLUEFIN' in answer['text'].upper(), answer
    with tempfile.TemporaryDirectory() as folder:
        audio = Path(folder)/'test.aiff'
        subprocess.run(['/usr/bin/say', '-o', str(audio), 'Hello, what time is it?'], check=True)
        send({'type': 'transcribe', 'path': str(audio)})
        transcript = read()
        assert transcript['type'] == 'transcript' and 'time' in transcript['text'].lower(), transcript
        assert not audio.exists(), 'Temporary recording should be removed'
    send({'type': 'quit'})
    p.wait(timeout=15)
    assert p.returncode == 0
    print('Standalone inference, declined action, transcription, and shutdown passed.')
finally:
    if p.poll() is None:
        p.terminate(); p.wait(timeout=15)
