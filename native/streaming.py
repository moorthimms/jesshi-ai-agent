"""Streaming local Ollama replies; actions still pass through the permission gate."""
import json
import re
import time
import urllib.request
import assistant
from features import configure_request


def chunks(payload):
    req = urllib.request.Request(assistant.URL + '/api/chat', data=json.dumps(payload).encode(),
                                 headers={'Content-Type': 'application/json'})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=180) as response:
        for line in response:
            if line.strip():
                packet = json.loads(line)
                if packet.get('error'):
                    raise ValueError(packet['error'])
                yield packet


def respond(messages, model, allowed, low_power, read_only, emit, source=chunks):
    started = time.monotonic()
    first = None
    for _ in range(6):
        payload = configure_request({'model': model, 'messages': messages,
            'stream': True, 'think': False, 'keep_alive': '15m',
            'tools': [t for t in assistant.TOOLS if t['function']['name'] in allowed]}, low_power, read_only)
        if not payload.get('tools'):
            payload.pop('tools', None)
        # Short default replies reduce completion latency; explicit long requests retain room.
        question = next((m.get('content', '') for m in reversed(messages) if m['role'] == 'user'), '')
        if not low_power and not re.search(r'\b(detailed|long|essay|full code|complete code|story|thorough)\b', question, re.I):
            payload['options']['num_predict'] = 256
        emit('answer_start')
        message = {'role': 'assistant', 'content': ''}
        speech = ''
        final_packet = {}
        for packet in source(payload):
            final_packet = packet
            part = packet.get('message', {})
            text = part.get('content', '')
            if text:
                if first is None:
                    first = time.monotonic() - started
                message['content'] += text
                emit('delta', text=text)
                speech += text
                while True:
                    boundary = next((m for m in re.finditer(r'[.!?](?:\s|$)', speech) if m.end() >= 12), None)
                    if not boundary or boundary.end() < 12:
                        break
                    emit('speech', text=speech[:boundary.end()].strip())
                    speech = speech[boundary.end():]
            if part.get('tool_calls'):
                message.setdefault('tool_calls', []).extend(part['tool_calls'])
        messages.append(message)
        calls = message.get('tool_calls', [])
        if not calls:
            if speech.strip():
                emit('speech', text=speech.strip())
            emit('timing', first_token_ms=round((first or 0) * 1000),
                 total_ms=round((time.monotonic() - started) * 1000),
                 tokens=final_packet.get('eval_count', 0))
            return message['content']
        for call in calls:
            fn = call['function']
            try:
                # A model returning a tool without a declaration is still denied.
                if fn['name'] not in allowed or read_only:
                    result = 'Action blocked by permission settings.'
                else:
                    result = assistant.execute(fn['name'], fn.get('arguments', {}))
            except Exception as exc:
                result = 'Action failed: ' + str(exc)
            messages.append({'role': 'tool', 'tool_name': fn['name'], 'content': result})
    return 'Stopped after six tool rounds. Please try a simpler request.'
