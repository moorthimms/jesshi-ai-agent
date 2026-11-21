# Jessy for iPhone and iPad

Open `Jessy.xcodeproj` in **Xcode 26 or newer**, select the Jessy target, then
choose your Apple development team and a unique bundle identifier under Signing
& Capabilities. Select your connected supported iPhone and Run. A free Personal
Team can be used for local device testing within Apple's provisioning limits;
TestFlight/App Store distribution needs the appropriate Apple developer account.

This project has no third-party dependencies. Minimum OS is iOS 26. It uses
Apple's **on-device** Foundation Models API, checks availability before each
request, and does not use Private Cloud Compute or another remote fallback.
A compatible Apple Intelligence iPhone, enabled Apple Intelligence, supported
region/language, and completed system model download are necessary for chat.
Notes/tasks/documents remain usable when the model is unavailable. Foundation
Models is best suited for writing, summaries, and extraction, not general coding
or complex reasoning. See https://developer.apple.com/documentation/FoundationModels/.

Implemented source: local chat, speech input forced to on-device recognition,
spoken output, document/PDF and screenshot OCR, document keyword retrieval,
editable memory, tasks, notifications, Apple Reminders and Calendar creation,
reviewed prompt routines with `jessy://routine?id=...` links for Shortcuts,
activity history, app lock with device authentication, thermal pause, short-answer
mode, text size, response language, undo for data changes, encrypted cross-platform
backups, and local Home Assistant light control with Keychain-stored credentials.
Every external device action has a confirmation preview and an OS permission gate.

Manual sync: export an encrypted backup, transfer with AirDrop/Files, import on
another Jessy version using the same password. This replaces data; it does not
merge concurrent edits or transfer permissions/tokens/model files. Native state
uses iOS complete file protection. Lock hides the app UI; backups use AES-GCM.

Limits: no unrestricted iPhone app control, arbitrary commands, automatic undo
for Apple Calendar/Reminders or smart-home actions, background AI, automatic cloud
sync, or model switching through Apple's system API. OS notification registrations
must be recreated on a receiving device. Voice input requires installed on-device
speech support for the selected locale. System speech voices vary by device.

## Validation status

The current development Mac has Command Line Tools but **no full Xcode/iOS SDK**.
Swift syntax parsing and project/plist validation pass. Shared crypto, retrieval,
and device-services code typechecks/builds against the Mac SDK; encrypted backups
round-trip between Swift and browser code. The iOS app has **not** been compiled,
signed, installed, or run on an iPhone. Do not treat this as a tested iOS release.

After installing Xcode, run:

```
xcodebuild -project ios/Jessy.xcodeproj -scheme Jessy \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Then test on a real supported iPhone: offline model chat, airplane mode restart,
microphone locale availability, cancellation/backgrounding, Face ID/passcode lock,
PDF/OCR limits, encrypted backup import/export, notification scheduling/cancellation,
calendar and reminders permission denial, and a local Home Assistant light action.
