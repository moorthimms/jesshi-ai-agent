import SwiftUI
import AppKit
import AVFoundation
import PDFKit
import Vision
import LocalAuthentication
import UniformTypeIdentifiers
import ServiceManagement
import NaturalLanguage
import ApplicationServices

struct ChatLine: Identifiable, Codable {
    var id = UUID()
    let role: String
    let text: String
}

struct MailBriefingView: View {
    @State private var unread: [String] = []
    @State private var status = ""
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inbox briefing").font(.headline)
                Text("Read unread subjects and senders from the first 30 messages in Apple Mail’s inbox. Add your Gmail or Outlook account in Apple Mail first.")
                Button("Read Apple Mail inbox", systemImage: "envelope") { loadInbox() }
                    .disabled(loading)
                if loading { ProgressView("Reading Apple Mail…") }
                if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
                ForEach(Array(unread.enumerated()), id: \.offset) { _, item in
                    Text(item).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private func loadInbox() {
        loading = true
        unread = []
        status = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", """
                with timeout of 20 seconds
                    tell application "/System/Applications/Mail.app"
                        set messageCount to count of messages of inbox
                        if messageCount > 30 then set messageCount to 30
                        set briefing to ""
                        repeat with idx from 1 to messageCount
                            set itemRef to message idx of inbox
                            if read status of itemRef is false then
                                set briefing to briefing & (sender of itemRef as text) & " — " & (subject of itemRef as text) & linefeed
                            end if
                        end repeat
                        return briefing
                    end tell
                end timeout
                """]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
                DispatchQueue.main.async {
                    loading = false
                    guard process.terminationStatus == 0 else {
                        status = "Could not read Apple Mail. Check Mail setup and macOS Privacy & Security → Automation."
                        return
                    }
                    unread = lines
                    if lines.isEmpty { status = "No unread messages in the scanned inbox messages." }
                }
            } catch {
                DispatchQueue.main.async {
                    loading = false
                    status = "Could not start the Apple Mail briefing."
                }
            }
        }
    }
}

struct ScreenNavigationView: View {
    @ObservedObject var agent: Agent
    @State private var appPID: pid_t = 0
    @State private var goal = ""
    @State private var applications: [NSRunningApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen navigation").font(.headline)
            Text("Choose an open app and describe one action. Jesshi uses the visible window’s accessibility labels to identify a control for you to review.")
            Picker("App", selection: $appPID) {
                Text("Select an app").tag(pid_t(0))
                ForEach(applications, id: \.processIdentifier) { app in
                    Text(app.localizedName ?? "App").tag(app.processIdentifier)
                }
            }
            Button("Refresh app list") { refresh() }
            TextField("Action, such as Show Downloads", text: $goal)
            Button("Find control", systemImage: "cursorarrow.click") {
                agent.findScreenControl(pid: appPID, goal: goal.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .disabled(!agent.ready || agent.busy || appPID == 0 || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text(agent.status).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .onAppear { refresh() }
    }

    private func refresh() {
        applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        if !applications.contains(where: { $0.processIdentifier == appPID }) { appPID = 0 }
    }
}

final class Agent: NSObject, ObservableObject, AVAudioRecorderDelegate, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var lines: [ChatLine] = []
    @Published var liveReply = ""
    @Published var latency = ""
    @Published var cloudVoiceID = UserDefaults.standard.string(forKey: "jessy.cloudVoiceID") ?? "" {
        didSet { UserDefaults.standard.set(cloudVoiceID, forKey: "jessy.cloudVoiceID") }
    }
    @Published var cloudVoiceKey = ""
    @Published private(set) var cloudVoiceActive = false
    private var cloudVoiceTask: Task<Void, Never>?
    private var cloudPlayer: AVAudioPlayer?
    private var pendingNavigation: (app: NSRunningApplication, window: AXUIElement, controls: [(AXUIElement, String)])?
    @Published var sessionAvailable = true
    let voice = VoiceController()
    @Published var voiceID = UserDefaults.standard.string(forKey: "jessy.voiceID") ?? "auto" { didSet { UserDefaults.standard.set(voiceID, forKey: "jessy.voiceID") } }
    @Published var voiceStyle = UserDefaults.standard.string(forKey: "jessy.voiceStyle") ?? "natural" { didSet { UserDefaults.standard.set(voiceStyle, forKey: "jessy.voiceStyle") } }
    @Published var voiceRate = UserDefaults.standard.object(forKey: "jessy.voiceRate") as? Double ?? 0.5 { didSet { UserDefaults.standard.set(voiceRate, forKey: "jessy.voiceRate") } }
    var installedVoices: [AVSpeechSynthesisVoice] { AVSpeechSynthesisVoice.speechVoices().sorted { ($0.language, $0.name) < ($1.language, $1.name) } }
    func configureVoice(_ utterance: AVSpeechUtterance) {
        if voiceID != "auto", let selected = AVSpeechSynthesisVoice(identifier: voiceID) { utterance.voice = selected }
        else if let language = NLLanguageRecognizer.dominantLanguage(for: utterance.speechString)?.rawValue {
            utterance.voice = installedVoices.first { $0.language.hasPrefix(language + "-") || $0.language == language }
        }
        utterance.pitchMultiplier = voiceStyle == "child" ? 1.35 : 1
        utterance.rate = Float(voiceRate)
    }
    func previewVoice() {
        guard !busy, !cloudVoiceActive else { return }
        speaker.stopSpeaking(at: .immediate); voice.suspend()
        let sample = AVSpeechUtterance(string: voice.recognitionLanguage == "ta" ? "வணக்கம்! நான் ஜெஸ்ஸி. உங்களுக்கு எப்படி உதவலாம்?" : "Hello! I’m Jessy. How can I help you?")
        configureVoice(sample); speaker.speak(sample)
    }
    weak var mainWindow: NSWindow?
    func raiseWindow() {
        mainWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func say(_ text: String) {
        guard speak, !text.isEmpty else { return }
        voice.suspend()
        let utterance = AVSpeechUtterance(string: text)
        configureVoice(utterance)
        speaker.speak(utterance)
    }
    func resumeHandsFree() {
        guard ready, !busy, !recording, !locked, !speaker.isSpeaking, !cloudVoiceActive else { return }
        voice.resume()
    }
    func speakWithCloudVoice(_ reply: String) {
        let voiceID = cloudVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = cloudVoiceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, voiceID.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            status = "Enter an ElevenLabs voice ID and API key in Voice settings."
            return
        }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)?output_format=mp3_44100_128") else { return }
        let text = String(reply.prefix(5000))
        approve("Send up to 5,000 characters of this reply to ElevenLabs for audio?") {
            speaker.stopSpeaking(at: .immediate)
            voice.suspend()
            cloudVoiceActive = true
            status = "Requesting ElevenLabs audio…"
            cloudVoiceTask = Task { @MainActor in
                let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
                defer { session.finishTasksAndInvalidate() }
                do {
                    var request = URLRequest(url: url, timeoutInterval: 25)
                    request.httpMethod = "POST"
                    request.setValue(key, forHTTPHeaderField: "xi-api-key")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(["text": text, "model_id": "eleven_multilingual_v2"])
                    let (audio, response) = try await session.data(for: request)
                    try Task.checkCancellation()
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard code == 200 else {
                        stopCloudVoice()
                        status = "ElevenLabs returned HTTP \(code). Check your key, voice ID, and plan."
                        resumeHandsFree()
                        return
                    }
                    let player = try AVAudioPlayer(data: audio)
                    player.delegate = self
                    cloudPlayer = player
                    guard player.play() else { throw CocoaError(.fileReadCorruptFile) }
                    status = "Playing ElevenLabs audio…"
                } catch {
                    guard !Task.isCancelled else { return }
                    stopCloudVoice()
                    status = "Could not play ElevenLabs audio."
                    resumeHandsFree()
                }
            }
        }
    }
    func stopCloudVoice() {
        cloudVoiceTask?.cancel()
        cloudVoiceTask = nil
        cloudPlayer?.stop()
        cloudPlayer = nil
        cloudVoiceActive = false
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.cloudPlayer === player else { return }
            self.stopCloudVoice()
            self.status = flag ? "Offline · \(self.modelName)" : "ElevenLabs playback ended early."
            self.resumeHandsFree()
        }
    }
    private func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
    private func focusedWindow(pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let value = axValue(application, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func controlLabel(_ element: AXUIElement) -> String? {
        guard (axValue(element, kAXEnabledAttribute) as? Bool) != false else { return nil }
        let role = axValue(element, kAXRoleAttribute) as? String
        guard [kAXButtonRole, "AXLink", kAXRadioButtonRole, kAXPopUpButtonRole].contains(role ?? "") else { return nil }
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              (actions as? [String])?.contains(kAXPressAction) == true else { return nil }
        let title = (axValue(element, kAXTitleAttribute) as? String) ?? (axValue(element, kAXDescriptionAttribute) as? String) ?? ""
        let label = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        return label.isEmpty ? nil : label
    }
    private func windowControls(_ window: AXUIElement) -> [(AXUIElement, String)] {
        var queue = [window]
        var controls: [(AXUIElement, String)] = []
        var index = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        while index < queue.count && index < 180 && controls.count < 35 && ProcessInfo.processInfo.systemUptime < deadline {
            let element = queue[index]
            index += 1
            if let label = controlLabel(element) { controls.append((element, label)) }
            var children: CFArray?
            if AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, 40, &children) == .success,
               let children = children as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return controls
    }
    func findScreenControl(pid: pid_t, goal: String) {
        guard ready, !busy, !locked, !goal.isEmpty else { return }
        guard goal.count <= 500 else { status = "Use at most 500 characters for the action."; return }
        stopCloudVoice()
        let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(promptOptions) else {
            status = "Allow Jesshi in macOS Privacy & Security → Accessibility, then try again."
            return
        }
        guard let app = NSRunningApplication(processIdentifier: pid), let window = focusedWindow(pid: pid) else {
            status = "No accessible focused window found. Open a window in the selected app."
            return
        }
        let controls = windowControls(window)
        guard !controls.isEmpty else { status = "No supported controls found in that window."; return }
        voice.suspend()
        pendingNavigation = (app, window, controls)
        busy = true
        status = "Finding a control locally…"
        send(["type": "navigate", "goal": goal, "controls": controls.map { $0.1 }])
    }
    private func finishNavigation(index: Int) {
        defer { pendingNavigation = nil; busy = false; resumeHandsFree() }
        guard let navigation = pendingNavigation, navigation.controls.indices.contains(index) else {
            status = "No matching control found."
            return
        }
        let (element, label) = navigation.controls[index]
        let app = navigation.app
        status = "Control ready for review."
        approve("Press “\(label)” in \(app.localizedName ?? "the selected app")?") {
            guard !app.isTerminated, let window = focusedWindow(pid: app.processIdentifier),
                  CFEqual(window, navigation.window), controlLabel(element) == label,
                  windowControls(window).contains(where: { CFEqual($0.0, element) }) else {
                status = "The window or control changed. Find the control again."
                return
            }
            let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
            status = result == .success ? "Pressed “\(label)”." : "The app did not accept the action."
        }
        if status == "Control ready for review." { status = "Screen action cancelled." }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in self?.speaking = self?.speaker.isSpeaking == true }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in self?.speaking = self?.speaker.isSpeaking == true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.resumeHandsFree() }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.speaking = self.speaker.isSpeaking
            self.resumeHandsFree()
        }
    }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    func setLaunchAtLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { status = "Login item: \(error.localizedDescription)" }
        objectWillChange.send()
    }
    @Published var library = LibraryState()
    @Published var showLibrary = false
    @Published var locked = false
    @Published var modelName = "Loading…"
    @Published var modelSize = ""
    @Published var availableModels: [String] = []
    @Published var services = DeviceServices()
    private var previousData: LibraryState?
    func checkpoint() { previousData = library }
    func undoData() {
        guard let previous = previousData else { status = "No library change to undo."; return }
        previousData = library; library = previous; lines = library.history; persist()
    }
    func undoAction() {
        guard ready, !busy else { return }
        busy = true; send(["type": "undo", "allowed": library.allowedTools])
    }
    func approve(_ title: String, action: () -> Void) {
        let alert = NSAlert(); alert.messageText = "Allow this action?"; alert.informativeText = title
        alert.addButton(withTitle: "Allow"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { action(); audit("Approved: " + title) }
    }
    func password(_ title: String) -> String? {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = "Enter your backup password (at least 12 characters). Keep it safe; it cannot be recovered."
        alert.accessoryView = field; alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }; return field.stringValue
    }
    func portableState() -> PortableState {
        var out = PortableState()
        out.chats = lines.filter { ["You", "Jessy", "Assistant"].contains($0.role) }.map { PortableChat(role: $0.role == "You" ? "user" : "assistant", content: $0.text) }
        out.documents = library.documents.map { PortableDocument(id: $0.id.uuidString, name: $0.name, text: $0.text) }
        out.tasks = library.tasks.map { PortableTask(id: $0.id.uuidString, title: $0.title, done: $0.done, due: $0.due.map { $0.timeIntervalSince1970 * 1000 }) }
        out.routines = library.routines ?? []; out.memory = library.memory; out.notes = library.notes
        out.activity = library.activity; out.language = library.language; out.lowPower = library.lowPower; out.fontSize = library.fontSize ?? 16; out.voice = speak
        return out
    }
    func applyPortable(_ state: PortableState) {
        checkpoint()
        library.history = state.chats.map { ChatLine(role: $0.role == "user" ? "You" : "Jessy", text: $0.content) }
        lines = library.history
        library.documents = state.documents.map { SavedDocument(id: UUID(uuidString: $0.id) ?? UUID(), name: $0.name, text: $0.text) }
        library.tasks = state.tasks.map { SavedTask(id: UUID(uuidString: $0.id) ?? UUID(), title: $0.title, done: $0.done, due: $0.due.map { Date(timeIntervalSince1970: $0 / 1000) }) }
        library.routines = state.routines; library.memory = state.memory; library.notes = state.notes; library.activity = state.activity
        library.language = state.language; library.lowPower = state.lowPower; library.fontSize = min(24, max(14, state.fontSize)); speak = state.voice; library.selectedDocument = nil
        persist()
    }
    private let stateURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Offline Assistant/jessy.json")
    func persist() {
        do {
            library.history = lines
            let bytes = try JSONEncoder().encode(library)
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        } catch { status = "Could not save: \(error.localizedDescription)" }
    }
    func audit(_ text: String) {
        library.activity.insert("\(Date().formatted()): \(text)", at: 0)
        library.activity = Array(library.activity.prefix(200)); persist()
    }
    func emergencyStop() {
        voice.setEnabled(false); shutdown(); liveReply = ""
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil; recording = false; ready = false; busy = false
        status = "Stopped. Completed actions cannot be reversed. Restart to continue."
        audit("Emergency stop requested")
    }
    func unlock() {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Jessy") { [weak self] success, error in
            DispatchQueue.main.async {
                if success { self?.locked = false }
                else { self?.status = error?.localizedDescription ?? "Authentication unavailable" }
            }
        }
    }
    func lock() { shutdown(); ready = false; busy = false; showLibrary = false; locked = true; status = "Locked · microphone paused" }
    func backup() {
        guard let pass = password("Export encrypted Jessy backup") else { return }
        do {
            let data = try BackupCrypto.seal(portableState(), password: pass)
            let panel = NSSavePanel(); panel.nameFieldStringValue = "Jessy-encrypted-backup.json"
            if panel.runModal() == .OK, let url = panel.url { try data.write(to: url, options: .atomic) }
        } catch { status = error.localizedDescription }
    }
    func restore() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 20_000_000 else { throw BackupError.invalid }
            if (try? JSONDecoder().decode(EncryptedBackup.self, from: data)) != nil {
                guard let pass = password("Restore encrypted Jessy backup") else { return }
                let restored = try BackupCrypto.open(data, password: pass)
                approve("Replace local chat, documents, tasks, memory, and notes with this backup?") { applyPortable(restored) }
            } else {
                let restored = try JSONDecoder().decode(LibraryState.self, from: data)
                approve("Replace Jessy data from a legacy unencrypted backup?") { checkpoint(); library = restored; lines = restored.history; persist() }
            }
        } catch { status = error.localizedDescription }
    }
    func importDocument() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, .pdf, .png, .jpeg]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        status = "Reading locally…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20_000_000 else { throw CocoaError(.fileReadTooLarge) }
                var text = ""
                if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
                    for i in 0..<min(pdf.pageCount, 100) { text += "[Page \(i + 1)]\n" + (pdf.page(at: i)?.string ?? "") + "\n" }
                } else if ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) {
                    text = try Self.recognizedText(in: VNImageRequestHandler(url: url))
                } else { text = try String(contentsOf: url, encoding: .utf8) }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                let extracted = String(text.prefix(120_000))
                DispatchQueue.main.async {
                    self.checkpoint(); self.library.documents.append(SavedDocument(name: url.lastPathComponent, text: extracted))
                    self.audit("Imported \(url.lastPathComponent)")
                    self.status = "Imported \(url.lastPathComponent). Select it in Library to ask questions."
                }
            } catch { DispatchQueue.main.async { self.status = "Import failed: \(error.localizedDescription)" } }
        }
    }
    func importClipboardScreenshot() {
        guard !locked else { return }
        let clipboard = NSPasteboard.general
        guard let image = clipboard.data(forType: .png) ?? clipboard.data(forType: .tiff) else {
            status = "Copy a screenshot to the clipboard first."
            return
        }
        guard image.count <= 20_000_000 else { status = "Choose an image under 20 MB."; return }
        status = "Reading screenshot locally…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let text = try Self.recognizedText(in: VNImageRequestHandler(data: image))
                DispatchQueue.main.async {
                    guard !self.locked else { return }
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        self.status = "No readable text found in the screenshot."
                        return
                    }
                    let document = SavedDocument(name: "Clipboard screenshot · \(Date().formatted())", text: String(text.prefix(120_000)))
                    self.checkpoint()
                    self.library.documents.append(document)
                    self.library.selectedDocument = document.id
                    self.audit("Imported clipboard screenshot")
                    self.status = "Screenshot selected. Ask about its text in Chat."
                }
            } catch {
                DispatchQueue.main.async {
                    guard !self.locked else { return }
                    self.status = "Could not read screenshot: \(error.localizedDescription)"
                }
            }
        }
    }
    private static func recognizedText(in handler: VNImageRequestHandler) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    @Published var input = ""
    @Published var status = "Starting bundled offline model…"
    @Published var busy = true
    @Published var ready = false
    @Published var planFirst = UserDefaults.standard.bool(forKey: "jessy.planFirst") {
        didSet { UserDefaults.standard.set(planFirst, forKey: "jessy.planFirst") }
    }
    @Published var recording = false
    @Published private(set) var speaking = false
    @Published var speak = true
    private var worker: Process?
    private var writer: FileHandle?
    private var reader: FileHandle?
    private var buffer = Data()
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    private let speaker = AVSpeechSynthesizer()

    override init() {
        super.init()
        speaker.delegate = self
        voice.canListen = { [weak self] in
            guard let self else { return false }
            return self.sessionAvailable && self.ready && !self.busy && !self.locked && !self.recording && !self.speaker.isSpeaking && !self.cloudVoiceActive
        }
        voice.onWake = { [weak self] in
            guard let self else { return }
            self.raiseWindow()
            self.voice.acknowledgeWake()
            self.speak = true
            let acknowledgement = AVSpeechUtterance(string: self.voice.recognitionLanguage == "ta" ? "சொல்லுங்க, நான் கேட்கிறேன்." : "Yes, I’m here. I’m listening.")
            self.configureVoice(acknowledgement)
            self.speaker.speak(acknowledgement)
        }
        voice.onCommand = { [weak self] text in
            guard let self, self.ready, !self.busy, !self.locked else { return }
            self.input = text; self.speak = true; self.raiseWindow(); self.submit()
        }
        if let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(LibraryState.self, from: data) {
            library = saved; lines = saved.history
        }
        locked = library.appLock
        if !locked { start() }
        voice.restorePreference()
    }
    func start() {
        guard worker?.isRunning != true, !locked else { return }
        busy = true; status = "Starting bundled offline model…"
        buffer.removeAll()
        guard let resources = Bundle.main.resourceURL else { return }
        let process = Process()
        process.executableURL = resources.appendingPathComponent("backend/backend")
        process.arguments = [resources.path]
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        process.environment = env
        let incoming = Pipe(), outgoing = Pipe()
        process.standardInput = incoming
        process.standardOutput = outgoing
        process.standardError = FileHandle.nullDevice
        writer = incoming.fileHandleForWriting
        reader = outgoing.fileHandleForReading
        reader?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { if self?.worker === process && process.isRunning { self?.receive(data) } }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.worker === process else { return }
                self?.ready = false
                self?.busy = false
                self?.status = "Local engine stopped. Quit and reopen the app."
            }
        }
        worker = process
        do { try process.run() }
        catch { status = "Could not start: \(error.localizedDescription)"; busy = false }
    }
    func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end)
            buffer.removeSubrange(...end)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            let text = obj["text"] as? String ?? ""
            switch type {
            case "ready":
                ready = true; busy = false
                availableModels = obj["models"] as? [String] ?? availableModels
                modelName = obj["model"] as? String ?? "local model"
                modelSize = obj["model_size"] as? String ?? ""
                status = "Offline · \(modelName)"
                resumeHandsFree()
            case "confirm":
                let alert = NSAlert()
                alert.messageText = "Allow this action?"
                alert.informativeText = text
                alert.addButton(withTitle: "Allow")
                alert.addButton(withTitle: "Cancel")
                send(["type": "confirm", "approved": alert.runModal() == .alertFirstButtonReturn])
            case "answer_start": liveReply = ""
            case "phase": status = text
            case "navigation": finishNavigation(index: obj["index"] as? Int ?? -1)
            case "delta": liveReply += text
            case "speech": say(text)
            case "timing":
                latency = "First text: \(obj["first_token_ms"] as? Int ?? 0) ms · Full reply: \(obj["total_ms"] as? Int ?? 0) ms"
            case "answer":
                status = "Offline · \(modelName)"
                lines.append(ChatLine(role: "Jessy", text: text)); persist()
                busy = false
                liveReply = ""
                if obj["streamed"] as? Bool != true { say(text) }
                resumeHandsFree()
            case "activity": audit(text)
            case "transcript":
                if text.isEmpty { busy = false; status = "No speech detected. Try again."; resumeHandsFree() }
                else { busy = false; input = text; submit() }
            case "reset":
                lines.removeAll(); persist(); busy = false
            case "error":
                if pendingNavigation != nil { status = "Could not find a screen control: \(text)" }
                pendingNavigation = nil
                lines.append(ChatLine(role: "Error", text: text)); busy = false; liveReply = ""; resumeHandsFree()
            default: break
            }
        }
    }
    func send(_ obj: [String: Any]) {
        guard let bytes = try? JSONSerialization.data(withJSONObject: obj) else { return }
        do { try writer?.write(contentsOf: bytes + Data([10])) }
        catch { status = "Connection lost: \(error.localizedDescription)"; busy = false }
    }
    func submit() {
        if ProcessInfo.processInfo.thermalState == .critical || ProcessInfo.processInfo.thermalState == .serious {
            status = "Mac is hot. Inference is paused until it cools."; return
        }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ready, !busy, !locked, !text.isEmpty else { return }
        stopCloudVoice()
        voice.suspend(); busy = true; speaker.stopSpeaking(at: .immediate)
        input = ""; liveReply = ""
        lines.append(ChatLine(role: "You", text: text))
        persist()
        let document = library.documents.first { $0.id == library.selectedDocument }
        send(["type": "chat", "text": text, "memory": library.memory,
              "context": retrievedExcerpt(document?.text ?? "", query: text),
              "source": document?.name ?? "", "language": voice.enabled ? "Auto" : library.language,
              "low_power": library.lowPower || ProcessInfo.processInfo.isLowPowerModeEnabled,
              "plan_first": planFirst,
              "allowed": library.allowedTools])
    }
    func reset() {
        stopCloudVoice()
        voice.suspend(); busy = true; speaker.stopSpeaking(at: .immediate); send(["type": "reset"])
    }
    func toggleRecording() {
        if recording { stopRecording(); return }
        stopCloudVoice()
        voice.suspend(); speaker.stopSpeaking(at: .immediate)
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if allowed && self.ready && !self.locked { self.beginRecording() }
                else { self.status = "Enable microphone access in System Settings → Privacy & Security → Microphone." }
            }
        }
    }
    private func beginRecording() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("offline-voice-\(UUID().uuidString).wav")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false]
        do {
            let audio = try AVAudioRecorder(url: url, settings: settings)
            guard audio.record() else { throw NSError(domain: "Microphone", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not start recording"]) }
            recorder = audio; recordingURL = url; recording = true
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in self?.stopRecording() }
        } catch { status = error.localizedDescription }
    }
    func stopRecording() {
        guard recording else { return }
        recordingTimer?.invalidate(); recordingTimer = nil
        recorder?.stop(); recorder = nil; recording = false; busy = true
        guard let url = recordingURL else { busy = false; return }
        send(["type": "transcribe", "path": url.path, "language": voice.recognitionLanguage])
        recordingURL = nil
    }
    func shutdown() {
        pendingNavigation = nil
        stopCloudVoice()
        cloudVoiceKey = ""
        voice.shutdown()
        recordingTimer?.invalidate(); recorder?.stop(); speaker.stopSpeaking(at: .immediate)
        reader?.readabilityHandler = nil
        try? writer?.close()
        if worker?.isRunning == true { worker?.terminate() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var agent: Agent?
    private var menuItem: NSStatusItem?
    func installWindow() {
        guard let agent else { return }
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            agent.mainWindow = window; window.delegate = self
        }
        guard menuItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Jessy"
        let menu = NSMenu()
        for (title, action) in [("Open Jessy", #selector(openJessy)), ("Pause hands-free listening", #selector(pauseListening)), ("Quit Jessy", #selector(quitJessy))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
        }
        item.menu = menu; menuItem = item
    }
    @objc func openJessy() { agent?.raiseWindow() }
    @objc func pauseListening() { agent?.voice.setEnabled(false) }
    @objc func quitJessy() { NSApp.terminate(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if agent?.voice.enabled == true { agent?.persist(); sender.orderOut(nil); return false }
        return true
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { agent?.raiseWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { agent?.voice.enabled != true }
    func applicationWillTerminate(_ notification: Notification) { agent?.persist(); agent?.shutdown() }
}

struct ContentView: View {
    @ObservedObject var agent: Agent
    @ObservedObject private var voice: VoiceController
    init(agent: Agent) { self.agent = agent; self.voice = agent.voice }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "waveform.circle.fill").font(.system(size: 38)).foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jessy").font(.title2.bold())
                    Text(agent.status).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                }
                Spacer()
                Toggle("Speak replies", isOn: $agent.speak).toggleStyle(.switch)
                Button("Library & Settings") { agent.showLibrary = true }.disabled(agent.busy || agent.recording)
                Button("Clear chat") { agent.reset() }.disabled(agent.busy || !agent.ready || agent.recording)
            }
            HStack {
                Button("Undo action") { agent.undoAction() }.disabled(!agent.ready || agent.busy)
                Button("Emergency stop", role: .destructive) { agent.emergencyStop() }
                if !agent.ready && !agent.busy { Button("Restart engine") { agent.start() } }
                Button("Lock", systemImage: "lock") { agent.lock() }
                Spacer()
                if let doc = agent.library.documents.first(where: { $0.id == agent.library.selectedDocument }) {
                    Text("Source: \(doc.name) · relevant excerpts").font(.caption)
                }
            }
            HStack {
                Toggle("Hi Jessy · hands-free", isOn: Binding(get: { voice.enabled }, set: { voice.setEnabled($0) }))
                Button("Talk to Jessy") { voice.beginConversation() }.disabled(!voice.enabled || !agent.ready || agent.busy)
                Button("Answer now") { voice.answerNow() }.disabled(!voice.enabled || agent.busy)
                Text(voice.status).font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if agent.lines.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Hi, I’m Jessy, your AI assistant.").font(.title3.bold())
                                Text("Ask a question, open Calculator, adjust volume, or save a note. Actions ask for your approval.")
                                Text("No account or internet connection needed. Click Record, speak, then click Stop.").foregroundColor(.secondary)
                            }.padding(20)
                        }
                        ForEach(agent.lines) { line in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(line.role).font(.caption.bold()).foregroundColor(.secondary)
                                Text(line.text).font(.system(size: agent.library.fontSize ?? 16)).textSelection(.enabled)
                                if line.role == "Jessy", !agent.cloudVoiceID.isEmpty {
                                    Button("Play with ElevenLabs", systemImage: "speaker.wave.2") {
                                        agent.speakWithCloudVoice(line.text)
                                    }.disabled(agent.busy || agent.recording || agent.cloudVoiceActive)
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(line.role == "You" ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.07))
                                .cornerRadius(12).id(line.id)
                        }
                        if !agent.liveReply.isEmpty {
                            VStack(alignment: .leading) { Text("Jessy · responding locally").font(.caption.bold()); Text(agent.liveReply).textSelection(.enabled) }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.07)).cornerRadius(12).id("live-reply")
                        }

                    }
                }.onChange(of: agent.lines.count) { _, _ in
                    if let last = agent.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }.onChange(of: agent.liveReply) { _, text in
                    if !text.isEmpty { proxy.scrollTo("live-reply", anchor: .bottom) }
                }
            }
            if agent.recording || agent.speaking || agent.busy {
                HStack {
                    if agent.recording { Label("Listening…", systemImage: "mic.fill") }
                    else if agent.speaking { Label("Speaking…", systemImage: "speaker.wave.2.fill") }
                    else {
                        ProgressView().controlSize(.small)
                        Text(agent.ready ? "Working locally…" : "Starting…")
                    }
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            HStack {
                TextField("Type a message…", text: $agent.input).textFieldStyle(.roundedBorder)
                    .onSubmit { if !agent.busy && !agent.recording { agent.submit() } }
                    .disabled(agent.busy || agent.recording || !agent.ready)
                Button(agent.recording ? "Stop" : "Record", systemImage: agent.recording ? "stop.fill" : "mic.fill") { agent.toggleRecording() }
                    .disabled(agent.busy || !agent.ready)
                Button("Send") { agent.submit() }.keyboardShortcut(.return, modifiers: .command)
                    .disabled(agent.busy || agent.recording || !agent.ready || agent.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(agent.latency.isEmpty ? "Qwen3 8B + Whisper · All inference stays on this Mac" : agent.latency).font(.caption2).foregroundColor(.secondary)
        }.accessibilityHidden(agent.locked).opacity(agent.locked ? 0 : 1).padding(22).frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $agent.showLibrary) { LibraryView(agent: agent).disabled(agent.busy) }
        .overlay {
            if agent.locked {
                VStack(spacing: 20) {
                    Text("Jessy is locked").font(.title)
                    Button("Unlock with Mac authentication") { agent.unlock() }
                    Text("After unlocking, click Restart engine.").font(.caption)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial)
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in
            agent.sessionAvailable = false; agent.voice.suspend()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            agent.sessionAvailable = false; agent.voice.suspend()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)) { _ in
            agent.sessionAvailable = true; agent.resumeHandsFree()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if agent.library.appLock && !agent.showLibrary && !agent.locked { agent.lock() }
        }
    }
}

@main struct OfflineAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var agent = Agent()
    var body: some Scene {
        WindowGroup {
            ContentView(agent: agent).onAppear { delegate.agent = agent; DispatchQueue.main.async { delegate.installWindow() }; NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 850, height: 650)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct SavedDocument: Identifiable, Codable {
    var id = UUID()
    var name: String
    var text: String
}
struct SavedTask: Identifiable, Codable {
    var id = UUID()
    var title: String
    var done = false
    var due: Date?
}
struct LibraryState: Codable {
    var routines: [PortableRoutine]?
    var fontSize: Double?
    var history: [ChatLine] = []
    var documents: [SavedDocument] = []
    var selectedDocument: UUID?
    var memory = ""
    var tasks: [SavedTask] = []
    var notes = ""
    var activity: [String] = []
    var language = "Auto"
    var lowPower = false
    var appLock = false
    var allowedTools = ["get_time", "get_volume", "set_volume", "open_app", "save_note"]
}
struct LibraryView: View {
    @ObservedObject var agent: Agent
    @State private var task = ""
    @State private var search = ""
    @State private var routineName = ""
    @State private var routinePrompt = ""
    @State private var due = Date().addingTimeInterval(3600)
    @State private var entity = "light.living_room"
    @State private var chosenModel = ""
    @ObservedObject private var services: DeviceServices
    @ObservedObject private var voice: VoiceController
    init(agent: Agent) { self.agent = agent; self.services = agent.services; self.voice = agent.voice }
    private let tools = [("get_time", "Read date and time"), ("get_volume", "Read volume"),
                         ("set_volume", "Change volume"), ("open_app", "Open supported apps"), ("save_note", "Save notes")]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Jessy Library & Settings").font(.title2.bold())
                Spacer()
                Button("Done") { agent.persist(); agent.showLibrary = false }
            }
            TabView {
                VStack(alignment: .leading) {
                    Text("Import a PDF, UTF-8 text file, or screenshot. Extraction happens on this Mac. Scanned PDFs need text extraction elsewhere.")
                    HStack {
                        Button("Import document or screenshot") { agent.importDocument() }
                        Button("Paste screenshot") { agent.importClipboardScreenshot() }
                        Button("Use general chat") { agent.library.selectedDocument = nil; agent.persist() }
                    }
                    TextField("Search document names and contents", text: $search)
                    List {
                        ForEach(agent.library.documents.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }) { doc in
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(doc.name).bold()
                                    Button(agent.library.selectedDocument == doc.id ? "Selected" : "Use in chat") { agent.library.selectedDocument = doc.id; agent.persist() }
                                    Button("Remove") { agent.checkpoint(); agent.library.documents.removeAll { $0.id == doc.id }; agent.persist() }
                                }
                                Text(String(doc.text.prefix(500))).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                    Text("Chat receives the relevant excerpts of the selected file. PDF page markers support checking citations. Answers may contain errors; check the original.").font(.caption)
                }.padding().tabItem { Label("Documents", systemImage: "doc.text") }
                VStack(alignment: .leading) {
                    Text("Personal memory").font(.headline)
                    Text("Only information you enter here is supplied as memory. Edit or delete it at any time.")
                    TextEditor(text: $agent.library.memory).frame(height: 110).border(Color.secondary.opacity(0.3))
                    Text("Notes").font(.headline)
                    TextEditor(text: $agent.library.notes).border(Color.secondary.opacity(0.3))
                    Text("Tasks").font(.headline)
                    HStack {
                        TextField("New task", text: $task)
                        Button("Add") {
                            guard !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            agent.checkpoint(); agent.library.tasks.append(SavedTask(title: task)); task = ""; agent.persist()
                        }
                    }
                    List {
                        ForEach($agent.library.tasks) { $item in
                            HStack {
                                Toggle(item.title, isOn: $item.done).onChange(of: item.done) { _, done in
                                    if done { services.cancel(id: item.id.uuidString) }; agent.persist()
                                }
                                Button("Schedule") {
                                    item.due = due; agent.persist()
                                    agent.approve("Schedule \(item.title) at \(due.formatted())?") { services.schedule(id: item.id.uuidString, title: item.title, date: due) }
                                }
                                Button("Apple Reminders") { agent.approve("Add \(item.title) to Apple Reminders?") { services.addReminder(item.title, date: item.due) } }
                                Button("Delete") { agent.checkpoint(); services.cancel(id: item.id.uuidString); agent.library.tasks.removeAll { $0.id == item.id }; agent.persist() }
                            }
                        }
                    }
                    DatePicker("Reminder / event time", selection: $due)
                    Button("Add calendar event from task field") { agent.approve("Create a one-hour event: \(task), \(due.formatted())?") { services.addEvent(task, date: due) } }.disabled(task.isEmpty)
                    Text(services.status).font(.caption).textSelection(.enabled)
                }.padding().tabItem { Label("Memory & Tasks", systemImage: "checklist") }
                ScrollView {
                    CalendarBriefingView(services: services)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }.tabItem { Label("Briefing", systemImage: "calendar") }
                MailBriefingView().tabItem { Label("Inbox", systemImage: "envelope") }
                ScreenNavigationView(agent: agent).tabItem { Label("Screen", systemImage: "cursorarrow") }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tool permissions").font(.headline)
                    ForEach(tools, id: \.0) { tool in
                        Toggle(tool.1, isOn: Binding(get: { agent.library.allowedTools.contains(tool.0) }, set: { enabled in
                            agent.library.allowedTools.removeAll { $0 == tool.0 }
                            if enabled { agent.library.allowedTools.append(tool.0) }
                            agent.persist()
                        }))
                    }
                    Text("Changes still require an Allow/Cancel preview. File access is limited to files you import; camera, arbitrary commands, and arbitrary app control are unavailable.")
                    Toggle("Require Mac authentication on launch and when leaving Jessy", isOn: $agent.library.appLock)
                    Text("App lock protects the interface. Saved data and backups are not encrypted by Jessy; use FileVault for disk protection.").font(.caption)
                    HStack { Button("Export backup") { agent.backup() }; Button("Restore backup") { agent.restore() } }
                    Text("Encrypted backups work across Jessy Mac, iPhone, and website. Transfer the backup with AirDrop, Files, or a drive; import it on the other device. OS permissions, app lock, and tool notes.txt are excluded.").font(.caption)
                    Button("Undo last library change") { agent.undoData() }
                    Spacer()
                }.padding().tabItem { Label("Privacy", systemImage: "hand.raised") }
                ScrollView { VStack(alignment: .leading, spacing: 12) {
                    Text("Voice & Tamil").font(.title2.bold())
                    Picker("Listening language", selection: $voice.recognitionLanguage) {
                        Text("Automatic").tag("auto"); Text("தமிழ் · Tamil").tag("ta"); Text("Hindi").tag("hi"); Text("Telugu").tag("te"); Text("Kannada").tag("kn"); Text("Malayalam").tag("ml"); Text("English").tag("en")
                    }
                    Text("For spoken Tamil, select Tamil to avoid language guessing. Recognition uses the larger offline Whisper small model.").font(.caption)
                    Picker("Reply voice", selection: $agent.voiceID) {
                        Text("Automatic by language").tag("auto")
                        ForEach(agent.installedVoices, id: \.identifier) { item in
                            Text("\(item.name) · \(item.language) · \(item.gender == .female ? "Woman" : item.gender == .male ? "Man" : "Other")").tag(item.identifier)
                        }
                    }
                    Picker("Voice style", selection: $agent.voiceStyle) {
                        Text("Natural adult voice").tag("natural")
                        Text("Playful child-like pitch").tag("child")
                    }
                    Text("Choose a woman or man voice above. Child-like style raises pitch; it is not a separately trained boy/girl voice.").font(.caption)
                    Slider(value: $agent.voiceRate, in: 0.35...0.65) { Text("Speaking speed") }
                    Button("Preview selected voice") { agent.previewVoice() }
                    Divider()
                    Text("ElevenLabs voice").font(.headline)
                    TextField("Voice ID", text: $agent.cloudVoiceID)
                    SecureField("API key for this session", text: $agent.cloudVoiceKey)
                    Text("Play a selected chat reply through ElevenLabs. Jesshi asks before sending reply text. Your API key stays in memory until you lock or quit.").font(.caption)
                    Link("Download more Apple voices", destination: URL(string: "https://support.apple.com/guide/mac-help/mchlp2290/mac")!)
                    Text("New Apple voices appear after downloading them in macOS Accessibility → Read & Speak / Spoken Content. They work offline after download.").font(.caption)
                }.padding() }.tabItem { Label("Voice & Tamil", systemImage: "waveform") }
                ScrollView { VStack(alignment: .leading, spacing: 12) {
                    Toggle("Hands-free Hi Jessy (microphone stays active)", isOn: Binding(get: { voice.enabled }, set: { voice.setEnabled($0) }))
                    Text("Close the window to keep the optional listener running in the menu bar. Quit Jessy stops it completely. Locking pauses microphone use. Wake recognition uses local Whisper; no recordings leave this Mac.").font(.caption)
                    Slider(value: $voice.silenceSeconds, in: 1...30, step: 1) { Text("Silence wait") }
                    Text("Wait \(Int(voice.silenceSeconds)) seconds after speech before answering (default 1). Lower this for quicker turn-taking.").font(.caption)
                    Text("Automatic speech detection ignores steady background noise when ending a turn. Nearby voices or television speech may still be detected.").font(.caption)
                    Button("Save voice timing") { voice.saveSettings() }
                    Toggle("Launch Jessy at login", isOn: Binding(get: { agent.launchAtLogin }, set: { agent.setLaunchAtLogin($0) }))
                    Text("Login launching may require approval in macOS Login Items. Mac must be awake and unlocked for hands-free use. Say ‘stop listening’ to return to wake-phrase mode.").font(.caption)
                    Text("Local model: \(agent.modelName)").font(.headline)
                    Text(agent.modelSize)
                    Text("Mac memory: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB. Bundled model selection respects a memory budget. Select another installed model below; import additional weights through the local model store described in README.")
                    Picker("Installed model", selection: $chosenModel) { ForEach(agent.availableModels, id: \.self) { Text($0).tag($0) } }
                    Button("Switch installed model") { agent.busy = true; agent.send(["type": "select_model", "model": chosenModel]) }.disabled(chosenModel.isEmpty || agent.busy)
                    Toggle("Plan with a second local model", isOn: $agent.planFirst)
                        .disabled(agent.availableModels.count < 2)
                    Text("Uses another installed model to outline an approach before answering. This adds time to each reply.").font(.caption)
                    Toggle("Low-power inference (shorter answers, two CPU threads)", isOn: $agent.library.lowPower)
                    Text("Mac Low Power Mode also enables these limits. Generation pauses during serious or critical thermal pressure.").font(.caption)
                    TextField("Reply language (Auto follows your language)", text: $agent.library.language)
                    Button("Use automatic reply language") { agent.library.language = "Auto"; agent.persist() }
                    Text("Offline speech: Hindi, Tamil, Telugu, Kannada, Malayalam, Bengali, Marathi, Gujarati, Punjabi, Assamese, Urdu, Nepali, Sanskrit, Sindhi and English. Accuracy varies; Odia is not supported by the bundled recognizer. Spoken replies require a matching installed macOS voice.").font(.caption)
                    Text("Offline: chat, microphone transcription, installed system voice, document reading, memory, tasks, and supported Mac controls.")
                    Slider(value: Binding(get: { agent.library.fontSize ?? 16 }, set: { agent.library.fontSize = $0 }), in: 14...24, step: 1) { Text("Text size") }
                    Text("Text size: \(Int(agent.library.fontSize ?? 16)) pt. Keyboard navigation and selectable text are available.").font(.caption)
                    Text("iPhone and web use their own local models. Use encrypted backups to transfer data between devices.").foregroundColor(.secondary)
                    Spacer()
                }.padding() }.tabItem { Label("Model & Offline", systemImage: "cpu") }
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Routine name", text: $routineName)
                    TextEditor(text: $routinePrompt).frame(height: 100)
                    Button("Save routine") {
                        agent.checkpoint(); agent.library.routines = (agent.library.routines ?? []) + [PortableRoutine(id: UUID().uuidString, name: routineName, prompt: routinePrompt)]
                        routineName = ""; routinePrompt = ""; agent.persist()
                    }.disabled(routineName.isEmpty || routinePrompt.isEmpty)
                    List(agent.library.routines ?? []) { routine in
                        HStack {
                            Text(routine.name)
                            Button("Review & run") { agent.input = routine.prompt; agent.showLibrary = false }
                            Button("Delete") { agent.checkpoint(); agent.library.routines?.removeAll { $0.id == routine.id }; agent.persist() }
                        }
                    }
                    Text("Routines prepare a chat request for review; device changes still need an action approval.").font(.caption)
                }.padding().tabItem { Label("Routines", systemImage: "play.circle") }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Local Home Assistant lights").font(.headline)
                    TextField("http://192.168.1.20:8123", text: $services.homeURL)
                    SecureField("Long-lived Home Assistant token", text: $services.homeToken)
                    Button("Save in Keychain") { services.saveHomeSettings() }
                    TextField("light.entity_id", text: $entity)
                    HStack {
                        Button("Turn on") { agent.approve("Turn on \(entity) using \(services.homeURL)?") { services.controlLight(entity: entity, on: true) } }
                        Button("Turn off") { agent.approve("Turn off \(entity) using \(services.homeURL)?") { services.controlLight(entity: entity, on: false) } }
                    }
                    Text(services.status)
                    Text("Requires your own configured Home Assistant server and compatible lights. Local HTTP sends the token over your LAN; use HTTPS when available. No internet or cloud inference is used.").font(.caption)
                    Spacer()
                }.padding().tabItem { Label("Home", systemImage: "house") }
                VStack(alignment: .leading) {
                    Text("Recent activity").font(.headline)
                    Text("Action attempts, results, imports, and stops. Completed actions are not automatically reversible.")
                    List(agent.library.activity, id: \.self) { Text($0).textSelection(.enabled) }
                    Button("Clear activity") { agent.library.activity = []; agent.persist() }
                }.padding().tabItem { Label("Activity", systemImage: "clock") }
            }
        }.padding(20).frame(width: 800, height: 640)
        .onDisappear { agent.persist() }
    }
}
