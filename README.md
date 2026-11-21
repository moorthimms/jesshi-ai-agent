# Jessy — offline assistant for Mac, website, and iPhone

The current Mac build is [dist/Offline Assistant.app](dist/Offline%20Assistant.app).
The website source/build is in `website/`; the native iPhone Xcode project is in
`ios/Jessy.xcodeproj`. See [FEATURE_STATUS.md](FEATURE_STATUS.md) for exact platform
capabilities and [ios/README.md](ios/README.md) for installation requirements.

Jessy 1.2 adds reviewed routines, scheduled local notifications, Apple Calendar and
Reminders create actions, undo for the last supported volume/note tool action,
undo for library changes, keyword-ranked document retrieval, text sizing, thermal
pauses, installed model selection, and configured local Home Assistant lights.
Cross-platform manual sync uses encrypted portable backups with a password.
Permissions, device credentials, and OS notification registrations stay local.
Routines load instructions for user review; they are not unrestricted scripts.

The website runs its own small WebLLM model after a one-time download. Chat, task
persistence, and UI were tested in Safari. The iPhone project uses Apple's on-device
Foundation Models and requires an eligible iOS 26+ iPhone. It is source-only here:
this development Mac lacks full Xcode/iOS SDK, so no iPhone build/install/test is
claimed. Native OS permission flows and real smart-home hardware need device QA.

Checks: 13 Python tests, 4 browser-code tests, Swift Mac typechecking/build,
website build, packaged Mac smoke test, and Swift↔web encrypted backup round-trip.
Older sections below describe the original builds and are retained for setup context;
the platform status document takes precedence over their feature limitations.

---

# Standalone Offline Assistant for Mac

The current standalone build is **dist/Offline Assistant.app**. Double-click it
for a native chat window. It contains Qwen3 8B weights, Whisper base, Python,
a private Ollama runtime, and all required inference libraries. It starts and
stops its own local inference process; no Terminal, Python installation,
separate Ollama app, account, or API key is required to use it.

Keep the `.app` intact. You can move it outside this project folder; its assets
are resolved relative to the app bundle. It targets Apple Silicon Macs with
macOS 14 or newer. This build is about 5.8 GB and is tuned for this 16 GB Mac.
It has a local ad-hoc signature, not a Developer ID/notarized distribution
signature. A second Mac has not been tested.

Click **Record**, speak, then **Stop** (recordings stop after 30 seconds).
Microphone access is requested on first use. Transcription is local, and the
temporary audio file is deleted after transcription. You can type instead.
**Speak replies** uses macOS speech synthesis with installed voices.
Actions such as changing volume, opening an app, and saving a note require an
Allow/Cancel dialog. Wake-word listening is not implemented.

Notes and runtime diagnostics are stored under
`~/Library/Application Support/Offline Assistant/`. Chat history is kept in
memory and cleared when you quit or click Clear chat. The private runtime
binds only to 127.0.0.1 on an automatically chosen port, uses the bundled model
store, and starts with `OLLAMA_NO_CLOUD=1`. No online fallback or model download
is performed by the app. Local OS permissions still apply to device controls.

Source files are in `native/`. To rebuild on this development Mac, install
PyInstaller into `.venv` and run `native/build.sh`; it copies the already
installed Ollama runtime and Qwen3 8B weights into the build. The existing
command-line assistant and launcher described below remain development tools.

---

# Offline Mac assistant

Uses your installed Ollama `qwen3:8b` model. No API key, cloud inference, or runtime model downloads. Text mode uses only Python's standard library. Requests go directly to 127.0.0.1:11434; cloud model entries are rejected.

## Run

Start Ollama if it is not running (`ollama serve` in another terminal), then:

```sh
python3 assistant.py --check
python3 assistant.py --speak
```

Try “What time is it?”, “Open Calculator”, “Set volume to 30”, or “Save a note: buy milk”. Opening apps, saving notes, and changing volume show the proposed action and require a typed `y`. Notes stay in `notes.txt` beside the script. The assistant cannot execute arbitrary shell commands. Chat history stays in process memory; `/reset` clears it and `/quit` exits. Ollama manages its own service logs.

## Offline microphone input (optional)

For this workspace, audio dependencies are installed in `.venv` and the setup
script downloads the multilingual base model into `models/whisper-base`.
After setup completes, double-click **Start Assistant.command** in Finder, or run:

```sh
.venv/bin/python assistant.py --speak --voice-model models/whisper-base
```

Press Enter to record. The recording lasts six seconds; wait for “Listening”
before speaking. You can also type at the same prompt. The launcher forces
Hugging Face offline mode. If audio input fails, the assistant keeps accepting
typed commands.

To reproduce the one-time setup on another Mac (requires internet):

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-voice.lock.txt
.venv/bin/python setup_voice.py
```

Check both Ollama and local speech-model loading without recording:

```sh
.venv/bin/python assistant.py --check --voice-model models/whisper-base
```

Transcribe an existing file without calling the LLM or executing actions:

```sh
.venv/bin/python assistant.py --voice-model models/whisper-base --audio-file recording.wav
```

Install the audio dependencies while online, or from an offline package cache:

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-voice.txt
python assistant.py --speak --voice-model /absolute/path/to/local/faster-whisper-model
```

The model directory must already contain a complete CTranslate2/faster-whisper model, including its tokenizer files. The app sets `local_files_only=True`; it does not download speech models. Grant Terminal microphone access in macOS settings when prompted. Press Enter to record six seconds, or use `--seconds 10`. This version uses push-to-talk; wake-word detection is not implemented. Spoken replies use macOS `say` and an installed system voice.

## Verification

```sh
python3 -m unittest discover -s tests
```

Tests check that invalid or unapproved actions cannot launch a process or change files. An actual microphone, speaker, and macOS permission check must be done interactively.

Protocol reference: https://docs.ollama.com/api/chat and https://docs.ollama.com/capabilities/tool-calling

Verified in this workspace: four unit tests pass; local `qwen3:8b` is reachable;
Whisper base loads with offline mode enabled; synthesized “Hello. What time is
it?” transcribes as “Hello, what time is it?”. The MacBook Pro microphone is
listed by macOS. Live microphone recording and permission approval remain for
the first interactive launch.

## Automatic local model selection and app launcher

Double-click `Offline Assistant.app` to open the assistant in Terminal. Keep the
app in this project directory: it launches the adjacent Python environment,
voice model, and scripts. This is a launcher app, not a standalone bundled GUI;
Ollama and its installed model weights remain a local dependency.

The default is now `--model auto`. The selector checks installed model sizes
against 45% of physical RAM, verifies completion and tool-calling support, and
rejects remote/cloud metadata (including aliases). Within that budget it
prefers the tested Qwen3 8B, then Qwen3 4B and Llama 3.2 variants; otherwise it
tries another fitting tool-capable model. This policy favors a practical voice
assistant and does not claim to benchmark model quality. On this 16 GB Mac,
it selects the already installed `qwen3:8b`.

Use `--model exact-local-name` to override the preference and memory filter;
local-only and tool-support checks still apply. If no suitable local model is
available, startup stops with an error. It never downloads or falls back to a
cloud model. Installed model weights, local Whisper transcription, and macOS
speech output allow operation with the internet disconnected. The app still
needs the local Ollama service running.

## Standalone validation

The packaged backend was run from `/tmp` with a minimal PATH, using only its
bundled executable, model, speech files, and private inference server. Local
chat/tool calling, an action approval followed by cancellation, offline
transcription of generated speech, temporary audio cleanup, and clean shutdown
passed. The native SwiftUI window also returned a local chat reply. Seven unit
tests pass. The app signature verifies after inference. A live microphone
recording remains for first use with macOS microphone permission.

## Jessy 1.1 feature update

The native app now introduces itself as Jessy. Build it with `native/build.sh`;
its existing on-disk location remains `dist/Offline Assistant.app`.

Implemented in the Mac app:

- Local chat and push-to-talk transcription, installed macOS speech output.
- Persisted chat display, editable personal memory, notes, and task checkboxes.
- Library import for UTF-8 text, text-based PDFs, and PNG/JPEG screenshots with
  local OCR. Search document names/content and choose one source for chat.
  Imports cap at 20 MB, PDFs at 100 pages, stored text at 120,000 characters,
  and chat context at the first 10,000 characters. PDF page markers are sent
  for citations; model-generated citations require checking. No vector search.
- Document chat disables device tools at both request and execution layers.
- Individual tool permissions plus existing Allow/Cancel action previews.
- Emergency stop terminates the local backend and stops recording/speaking.
  Already completed actions are not rolled back. Restart the engine to resume.
- Activity history, backup export/restore, and Mac authentication app lock.
  Locking stops the engine; unlock and restart to resume. The lock hides the
  interface; it does not encrypt the data or backups. macOS FileVault remains
  the disk protection mechanism. Library settings are saved on closing settings
  and quitting. Backups contain sensitive imported text and personal memory.
- Preferred reply language, offline feature status, model size/RAM information,
  and low-power response limits. Mac Low Power Mode also activates the limits.

Local state is `~/Library/Application Support/Offline Assistant/jessy.json`;
legacy tool-created notes remain in the adjacent `notes.txt`. Backups include
JSON state, not model weights, OS permissions, or that legacy notes file.

Still requiring separate implementation: native iPhone app, offline website,
device sync, custom routines, scheduled reminders/Apple Calendar integration,
smart-home integrations, arbitrary app/file automation, automatic action undo,
model installation/switching, thermal-aware pauses, and broader accessibility
QA. No UI placeholder is presented as a working integration. Document search
is local text search, not semantic retrieval. Saved conversation display is
restored, but model context starts fresh each launch. Voice output uses the
system's installed/default voice rather than a multilingual voice selector.

Verification: run `python3 -m unittest discover -s tests` and
`python3 native/smoke_standalone.py`. Interactive microphone permission,
Touch ID/password locking, VoiceOver, and backup dialogs require native UI QA.

### Hands-free Jessy on Mac

In Settings → Model & Offline, enable **Hands-free Hi Jessy** and grant microphone
access. Close the window to leave Jessy in the menu bar, then say **Hi Jessy**.
Jessy opens, listens to your request, and answers automatically after **1 second
of silence**. Reduce the silence wait (1–30 seconds) for faster turn-taking. A local neural speech detector ends turns without using background loudness. Spoken replies
stream sentence by sentence; the microphone pauses during replies. Say “stop
listening” to return to wake-phrase mode, or use the menu-bar Pause control.

Enable Launch Jessy at login if desired. The Mac must remain awake and unlocked.
Quit stops the listener completely; voice cannot reopen a fully quit app. Wake
recognition and transcription run locally, and temporary audio is deleted.
The website streams answers too, but cannot listen when its browser is closed.

Indian-language voice input uses automatic language detection. Bundled Whisper
support includes Hindi, Tamil, Telugu, Kannada, Malayalam, Bengali, Marathi,
Gujarati, Punjabi, Assamese, Urdu, Nepali, Sanskrit, and Sindhi; accuracy varies.
Odia and several other Indian languages need an additional speech model.
Hands-free replies follow the request language; installed matching Mac voices
are selected automatically when available. Existing long silence preferences
are migrated to a new one-second default.

Voice turn-ending now uses local Silero speech detection, with one-second
checks during conversation. Audio chunks are retained while recognition is busy.
A 45-second turn limit prevents indefinite listening. Steady synthetic noise and
silence were rejected in testing; nearby conversations and TV can still count as speech.

### Voice and Tamil settings

Model & Offline now includes a persistent reply-voice picker, previews, speaking
speed, and an optional child-like pitch style. The list reflects actual installed
Apple voices and their reported gender; child-like pitch is an effect, not a
separately trained child model. Download additional voices through macOS
Accessibility → Read & Speak / Spoken Content, then reopen Settings.

Select Tamil under Listening language for Tamil conversations. This pins local
recognition to Tamil for both Record and hands-free turns, retains Tamil script,
and requests conversational Tamil answers. Whisper small replaces base; final
transcription uses a wider decoding beam. This increases recognition work and
memory, so speed and accuracy still depend on audio and hardware. No claim of
universal dialect accuracy or perfect noise removal is made.
