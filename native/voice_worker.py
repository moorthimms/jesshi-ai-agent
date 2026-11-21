"""Local Whisper wake phrase and continuous utterance transcription over stdio."""
import json
from pathlib import Path
import re
import sys
import wave

WAKE = re.compile(r'\b(?:hi|hey|hello|hhi)\s*[,!.]?\s*(?:jessy|jessie|jesse|jessica)\b[,.!?:\s]*', re.I)


def strip_wake(text):
    match = WAKE.search(text)
    return text[match.end():].strip() if match else None


def run(resources):
    import numpy as np
    import assistant
    from faster_whisper.vad import get_speech_timestamps, VadOptions
    model = assistant.load_voice_model(resources / 'speech')
    audio = np.empty(0, dtype=np.float32)
    awake = False
    language = None
    def emit(kind, **fields):
        print(json.dumps(dict(type=kind, **fields)), flush=True)
    emit('voice_ready')
    for line in sys.stdin:
        obj = json.loads(line)
        generation = obj.get('generation')
        try:
            kind = obj['type']
            if kind == 'quit':
                break
            if kind == 'reset':
                awake = obj.get('awake') is True
                requested = obj.get('language', 'auto')
                language = requested if requested in ('ta','hi','te','kn','ml','en','bn','mr','gu','pa','ur') else None
                audio = np.empty(0, dtype=np.float32)
                continue
            if kind not in ('chunk', 'finish'):
                raise ValueError('Unsupported voice operation')
            path = Path(obj['path']).resolve()
            if not path.name.startswith('jessy-listen-') or path.suffix != '.wav':
                raise ValueError('Invalid voice recording path')
            try:
                with wave.open(str(path), 'rb') as wav:
                    if wav.getframerate() != 16000 or wav.getnchannels() != 1 or wav.getsampwidth() != 2:
                        raise ValueError('Expected 16 kHz mono PCM audio')
                    if wav.getnframes() > 16000 * 100:
                        raise ValueError('Voice chunk is too long')
                    samples = np.frombuffer(wav.readframes(wav.getnframes()), dtype=np.int16).astype(np.float32) / 32768
            finally:
                path.unlink(missing_ok=True)
            audio = np.concatenate((audio, samples))
            audio = audio[-16000 * (90 if awake else 7):]
            if awake and kind == 'chunk':
                speech = get_speech_timestamps(audio, VadOptions(min_speech_duration_ms=200, min_silence_duration_ms=300))
                trailing = (len(audio) - speech[-1]['end']) / 16000 if speech else 0
                emit('voice_result', text='', wake=False, has_speech=bool(speech),
                     trailing_silence=trailing, generation=generation)
                continue
            segments, _ = model.transcribe(audio, beam_size=3 if awake else 1, vad_filter=True,
                condition_on_previous_text=False, language='en' if not awake else language, task='transcribe')
            text = ' '.join(s.text for s in segments).strip()
            tail = strip_wake(text)
            detected = tail is not None
            if detected:
                if not awake:
                    # English wake detection must not force the following Indian-language request into English.
                    segments, _ = model.transcribe(audio, beam_size=3 if awake else 1, vad_filter=True,
                        condition_on_previous_text=False, language=language, task='transcribe')
                    multilingual = ' '.join(s.text for s in segments).strip()
                    text = strip_wake(multilingual)
                    if text is None:
                        text = multilingual or tail
                else:
                    text = tail
                awake = True
            if kind == 'finish':
                emit('voice_final', text=text, generation=generation)
                audio = np.empty(0, dtype=np.float32)
                awake = False
            else:
                emit('voice_result', text=text if awake else '', wake=detected, generation=generation)
        except Exception as exc:
            emit('voice_error', text=str(exc), generation=generation)
