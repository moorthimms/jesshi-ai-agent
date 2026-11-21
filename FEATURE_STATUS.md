# Jessy platform status

| Feature | Mac bundle | Website | iPhone source |
|---|---|---|---|
| Offline AI | Bundled Qwen3 8B | WebLLM/WebGPU, initial download | Apple on-device model, eligible iOS 26+ device |
| Voice input | Local Whisper | Not available | On-device speech recognizer, locale dependent |
| Spoken replies | Installed Mac voice | Local browser voice | System voice |
| Text/PDF questions | Yes, ranked excerpts | Yes, ranked excerpts | Yes, ranked excerpts |
| Screenshot OCR | Yes | Not available | Yes |
| Memory, notes, tasks | Yes | Yes | Yes |
| Routines | Reviewed prompt shortcuts | Reviewed prompt shortcuts | Reviewed prompt shortcuts + URL links |
| Scheduled reminders | OS notifications | While app open | OS notifications |
| Apple Calendar/Reminders | Explicit create actions | Not available | Explicit create actions |
| Calendar briefing | Today / next 7 days with Apple Calendar permission | Not available | Today / next 7 days with Apple Calendar permission |
| Inbox briefing | Unread sender and subject through Apple Mail | Not available | Not available |
| Cloud voice | ElevenLabs playback for selected replies | Not available | Not available |
| Two-model planning | Optional local planner before local replies | Not available | Not available |
| Screen navigation | Local model proposes one accessible control for approval | Not available | Not available |
| Action preview/permissions | Tool switches + approval | No device actions | Approval + OS permission gates |
| Emergency stop | Kills local engine, stops voice | Interrupts generation/voice | Cancels generation/recording/voice |
| Undo | Last volume/note tool + library changes | Last data edit | Last data edit |
| Activity history | Yes | Yes | Yes |
| Authentication lock | Mac device auth | Device/browser account only | Device auth |
| Encrypted backup/manual sync | Shared portable format | Shared portable format | Shared portable format |
| Low power/thermal | Thread/token limits + thermal pause | Token limits | Concise mode + thermal pause |
| Languages/text size | Yes | Yes | Yes |
| Model management | Installed model selection | Download/load/remove two model sizes | OS-managed model; availability status |
| Local smart-home control | Configured Home Assistant lights | Not available | Configured Home Assistant lights |

Manual sync transfers a snapshot; it does not automatically merge changes. No
version provides unlimited device control, background cloud sync, or universal
undo. OS restrictions apply. Home Assistant requires actual configured hardware.

Mac is locally built and tested. Website UI/persistence and browser model loading
are verified in Safari; see build-cache for test logs. iPhone is source-only,
uncompiled here because full Xcode and an iOS SDK are absent. VoiceOver, real
calendar/reminder writes, Touch ID/Face ID, local light control, and iPhone runtime
verification require device/permission testing. No such test is claimed complete.

Mac hands-free mode is opt-in: local “Hi Jessy” recognition keeps running when
the window is closed, with a menu-bar pause/quit control. Fully quitting, sleeping,
or locking stops listening. It waits 1 second of silence by default (adjustable
1–30 seconds), then streams and speaks the reply. Temporary audio stays local
and is deleted. Speech detection threshold is adjustable for background noise.
Mac and website stream replies and speak completed sentences. A closed browser
cannot listen. Synthetic wake audio, silence timing, streaming, and bundled
inference were tested; physical microphone turn-taking still needs device testing.

Indian-language voice input uses automatic language detection. Bundled Whisper
support includes Hindi, Tamil, Telugu, Kannada, Malayalam, Bengali, Marathi,
Gujarati, Punjabi, Assamese, Urdu, Nepali, Sanskrit, and Sindhi; accuracy varies.
Odia and several other Indian languages need an additional speech model.
Hands-free replies follow the request language; installed matching Mac voices
are selected automatically when available. Existing long silence preferences
are migrated to a new one-second default.

Mac voice settings now expose installed Apple voices by name/language/reported
gender, preview, speed, and an optional child-like pitch effect. Tamil can be
pinned as the listening language for Record and hands-free input, avoiding
automatic language switching. The small multilingual speech model replaces base.
These improvements do not establish accuracy for every dialect or microphone.

On Mac, **Library & Settings → Briefing** reads Apple Calendar on request. On
iPhone, the same view is in **Tasks → Calendar briefing**. Full calendar access
is required to read events. Briefing entries stay in the view and are not added
to chat history or backups. Mac users can also paste a copied screenshot in the
library to run local OCR and select its extracted text for chat.

Mac **Library & Settings → Inbox** reads unread message subjects and senders
from Apple Mail after macOS Automation permission. Connect Gmail or Outlook
inside Apple Mail. **Screen** uses macOS Accessibility permission to identify
a control in the selected app and asks before pressing it. **Model & Offline**
can enable planning with another installed model. **Voice & Tamil** accepts
an ElevenLabs voice ID and session key for individual reply playback.
