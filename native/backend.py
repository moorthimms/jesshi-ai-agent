"""Private stdio backend, packaged with Python and local speech recognition."""
import atexit
import json
import multiprocessing
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time
import assistant
from actions import UndoManager
from streaming import respond as respond_stream
from features import turn_settings, configure_request


def emit(kind, **fields):
    print(json.dumps(dict(type=kind, **fields)), flush=True)


def main():
    resources = Path(sys.argv[1]).resolve()
    data = Path.home() / 'Library/Application Support/Offline Assistant'
    data.mkdir(parents=True, exist_ok=True)
    # Save user notes outside the immutable application bundle.
    assistant.__file__ = str(data / 'assistant.py')
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    assistant.URL = f'http://127.0.0.1:{port}'
    env = {k: v for k, v in os.environ.items() if not k.startswith('OLLAMA_')}
    env.update(OLLAMA_HOST=f'127.0.0.1:{port}', OLLAMA_MODELS=str(resources / 'models'),
               OLLAMA_NO_CLOUD='1', OLLAMA_NOPRUNE='1', OLLAMA_CONTEXT_LENGTH='4096',
               OLLAMA_KEEP_ALIVE='15m', OLLAMA_NUM_PARALLEL='1', HF_HUB_OFFLINE='1', HF_HUB_DISABLE_TELEMETRY='1',
               HOME=str(data))
    log = (data / 'runtime.log').open('a')
    server = subprocess.Popen([str(resources / 'runtime/ollama'), 'serve'], env=env,
                              stdout=log, stderr=log, start_new_session=True)
    def cleanup():
        try:
            os.killpg(server.pid, signal.SIGTERM)
            server.wait(timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            try:
                os.killpg(server.pid, signal.SIGKILL)
            except OSError:
                pass
        log.close()
    atexit.register(cleanup)
    def terminate(*_):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, terminate)
    for _ in range(120):
        if server.poll() is not None:
            raise RuntimeError('Bundled inference runtime stopped. See runtime.log in Application Support/Offline Assistant.')
        try:
            models = assistant.request('/api/tags')['models']
            break
        except Exception:
            time.sleep(0.25)
    else:
        raise RuntimeError('Local runtime did not start in time.')
    model = assistant.select_model(models)
    transcriber = None
    messages = [{'role': 'system', 'content': assistant.SYSTEM}]
    # Load the model before announcing readiness so the first turn avoids a cold load.
    assistant.request('/api/chat', {'model': model, 'messages': [{'role': 'user', 'content': 'Hi'}], 'stream': False, 'think': False, 'keep_alive': '15m', 'options': {'num_predict': 1, 'num_ctx': 4096}})
    emit('ready', model=model, models=[m['name'] for m in models], model_size=f"Bundled weights: {sum(m.get('size', 0) for m in models) / 1_000_000_000:.1f} GB")
    def confirm(prompt):
        emit('confirm', text=prompt.removesuffix(' [y/N] '))
        reply = sys.stdin.readline()
        if not reply:
            raise SystemExit(0)
        return 'y' if json.loads(reply).get('approved') is True else 'n'
    original_execute = assistant.execute
    undo = UndoManager()
    undo.original = original_execute
    allowed = set()
    def guarded_execute(name, args):
        if name not in allowed:
            emit('activity', text=f'Denied by permissions: {name}')
            return 'Action blocked by your Jessy permission settings.'
        emit('activity', text=f'Action requested: {name}')
        try:
            result = undo.execute(name, args, confirm)
        except Exception as exc:
            emit('activity', text=f'Action failed: {name}: {exc}')
            raise
        emit('activity', text=result)
        return result
    assistant.execute = guarded_execute
    original_request = assistant.request
    low_power = False
    read_only_context = False
    def configured_request(path, payload=None):
        if path == '/api/chat' and payload:
            payload = configure_request(payload, low_power, read_only_context)
        return original_request(path, payload)
    assistant.request = configured_request
    for line in sys.stdin:
        try:
            command = json.loads(line)
            kind = command['type']
            if kind == 'quit':
                break
            if kind == 'reset':
                messages = messages[:1]
                emit('reset')
                continue
            if kind == 'undo':
                permissions = set(command.get('allowed', []))
                result = undo.undo(permissions, confirm)
                emit('activity', text=result)
                emit('answer', text=result)
                continue
            if kind == 'select_model':
                model = assistant.select_model(models, command['model'])
                messages = messages[:1]
                emit('ready', model=model)
                continue
            if kind == 'transcribe':
                if transcriber is None:
                    transcriber = assistant.load_voice_model(resources / 'speech')
                try:
                    requested = command.get('language', 'auto')
                    language = requested if requested in ('ta','hi','te','kn','ml','en','bn','mr','gu','pa','ur') else None
                    segments, _ = transcriber.transcribe(command['path'], beam_size=3, vad_filter=True, language=language, task='transcribe')
                    text = ' '.join(s.text for s in segments).strip()
                finally:
                    Path(command['path']).unlink(missing_ok=True)
                emit('transcript', text=text)
            elif kind == 'chat':
                allowed, prompt, system, read_only_context = turn_settings(command)
                low_power = command.get('low_power') is True
                messages[0] = {'role': 'system', 'content': system}
                if len(messages) > 13:
                    messages[:] = messages[:1] + messages[-12:]
                turn = {'role': 'user', 'content': prompt}
                messages.append(turn)
                try:
                    answer = respond_stream(messages, model, allowed, low_power, read_only_context, emit)
                finally:
                    # Do not retain repeated attachment excerpts in conversation context.
                    turn['content'] = command['text']
                emit('answer', text=answer, streamed=True)
            else:
                raise ValueError('Unsupported request')
        except Exception as exc:
            emit('error', text=str(exc))

if __name__ == '__main__':
    multiprocessing.freeze_support()
    try:
        if '--voice-only' in sys.argv:
            from voice_worker import run
            run(Path(sys.argv[1]).resolve())
        else:
            main()
    except Exception as exc:
        emit('error', text=str(exc))
        raise SystemExit(1)
