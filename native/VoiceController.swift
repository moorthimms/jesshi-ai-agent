import Foundation
import AVFoundation

struct VoiceSilenceClock {
    var began: TimeInterval = 0
    var lastSpeech: TimeInterval?
    var silenceSeconds: TimeInterval = 1
    mutating func begin(at now: TimeInterval) { began = now; lastSpeech = nil }
    mutating func speech(at now: TimeInterval) { lastSpeech = now }
    func shouldFinish(at now: TimeInterval) -> Bool { lastSpeech.map { now - $0 >= silenceSeconds } ?? false }
    func abandoned(at now: TimeInterval) -> Bool { lastSpeech == nil && now - began >= 30 }
}

final class VoiceController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var status = "Hands-free listening is off"
    @Published var silenceSeconds: Double = UserDefaults.standard.object(forKey: "jessy.silence.v2") as? Double ?? 1
    @Published var threshold: Double = UserDefaults.standard.object(forKey: "jessy.voiceThreshold") as? Double ?? -38
    @Published var recognitionLanguage: String = UserDefaults.standard.string(forKey: "jessy.recognitionLanguage") ?? "auto" { didSet {
        UserDefaults.standard.set(recognitionLanguage, forKey: "jessy.recognitionLanguage")
        if enabled { suspend(); resume() }
    }}
    var canListen: () -> Bool = { false }
    var onWake: () -> Void = {}
    var onCommand: (String) -> Void = { _ in }
    private var process: Process?
    private var writer: FileHandle?
    private var reader: FileHandle?
    private var buffer = Data()
    private var recorder: AVAudioRecorder?
    private var url: URL?
    private var timer: Timer?
    private var chunkStart = Date()
    private var clock = VoiceSilenceClock()
    private var generation = UUID().uuidString
    private var awaiting = false
    private var ready = false
    private var engaged = false
    private var latestEnergy: TimeInterval?
    private var finishing = false
    private var acknowledging = false
    private var files: Set<URL> = []
    private let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]

    func restorePreference() {
        if UserDefaults.standard.bool(forKey: "jessy.handsFree") { setEnabled(true) }
    }
    func setEnabled(_ value: Bool) {
        if !value {
            enabled = false; UserDefaults.standard.set(false, forKey: "jessy.handsFree")
            shutdown(); status = "Hands-free listening is off"; return
        }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self else { return }
                guard allowed else { self.status = "Microphone permission is needed for Hi Jessy."; return }
                self.enabled = true; UserDefaults.standard.set(true, forKey: "jessy.handsFree")
                self.startWorker()
            }
        }
    }
    func saveSettings() {
        silenceSeconds = min(30, max(1, silenceSeconds))
        threshold = min(-15, max(-60, threshold))
        UserDefaults.standard.set(silenceSeconds, forKey: "jessy.silence.v2")
        UserDefaults.standard.set(threshold, forKey: "jessy.voiceThreshold")
    }
    private func startWorker() {
        guard process?.isRunning != true, let resources = Bundle.main.resourceURL else { resume(); return }
        status = "Loading local wake-phrase recognition…"
        let p = Process(); p.executableURL = resources.appendingPathComponent("backend/backend")
        p.arguments = [resources.path, "--voice-only"]
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"; env["HF_HUB_DISABLE_TELEMETRY"] = "1"; p.environment = env
        let input = Pipe(), output = Pipe(); p.standardInput = input; p.standardOutput = output; p.standardError = FileHandle.nullDevice
        writer = input.fileHandleForWriting; reader = output.fileHandleForReading
        reader?.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { if self?.process === p { self?.receive(bytes) } }
        }
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async {
            guard let self, self.process === p else { return }
            self.suspend(); self.ready = false
            if self.enabled { self.status = "Voice engine stopped. Turn hands-free off and on to restart." }
        }}
        process = p
        do { try p.run() } catch { status = error.localizedDescription }
    }
    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        do { try writer?.write(contentsOf: data + Data([10])) }
        catch { ready = false; status = "Voice connection lost"; suspend() }
    }
    private func receive(_ bytes: Data) {
        buffer.append(bytes)
        while let end = buffer.firstIndex(of: 10) {
            let data = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = obj["type"] as? String else { continue }
            if type == "voice_ready" { ready = true; resume(); continue }
            guard obj["generation"] as? String == generation, enabled else { continue }
            if acknowledging { continue }
            awaiting = false
            let text = obj["text"] as? String ?? ""
            if type == "voice_error" { status = text; finishing = false; suspend(); continue }
            if type == "voice_result", !finishing, obj["wake"] as? Bool == true, !engaged {
                engaged = true; clock.begin(at: Date.timeIntervalSinceReferenceDate); clock.speech(at: latestEnergy ?? Date.timeIntervalSinceReferenceDate)
                status = "Hi Jessy heard. Listening for your sentence…"; onWake()
            }
            if type == "voice_result", engaged, !finishing, obj["has_speech"] as? Bool == true {
                if let trailing = obj["trailing_silence"] as? Double, trailing >= silenceSeconds { finish(); continue }
            }
            if type == "voice_final" {
                finishing = false
                let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if ["stop listening", "stop conversation", "goodbye jessy", "goodbye", "go to sleep"].contains(normalized) {
                    engaged = false; status = "Conversation ended. Listening for Hi Jessy."; resume(); continue
                }
                if text.isEmpty { engaged = true; status = "I’m here. Ask your question."; resume() }
                else { status = "Sentence complete. Answering locally…"; onCommand(text) }
            }
        }
    }
    func resume() {
        guard enabled, canListen() else { return }
        if !ready && process?.isRunning != true { startWorker(); return }
        guard ready, timer == nil, !finishing else { return }
        if acknowledging {
            acknowledging = false
        } else {
            generation = UUID().uuidString; awaiting = false
            send(["type": "reset", "awake": engaged, "language": recognitionLanguage, "generation": generation])
        }
        clock.begin(at: Date.timeIntervalSinceReferenceDate); clock.silenceSeconds = silenceSeconds
        status = engaged ? "Listening for your next sentence…" : "Listening locally for Hi Jessy"
        do { try beginChunk() }
        catch { status = error.localizedDescription; return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
    }
    func acknowledgeWake() {
        // Keep already captured question audio; exclude our spoken acknowledgement.
        timer?.invalidate(); timer = nil; recorder?.stop(); recorder = nil
        if let url { try? FileManager.default.removeItem(at: url) }; url = nil
        acknowledging = true
        status = "Yes, I’m here. Ask your question."
    }
    func beginConversation() {
        guard enabled, ready, canListen() else { return }
        engaged = true; onWake()
    }
    func answerNow() {
        guard engaged, !finishing, !acknowledging, timer != nil else { return }
        finish()
    }
    private func beginChunk() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("jessy-listen-\(UUID().uuidString).wav")
        let audio = try AVAudioRecorder(url: path, settings: settings)
        audio.isMeteringEnabled = true
        guard audio.record() else { throw CocoaError(.fileWriteUnknown) }
        recorder = audio; url = path; files = files.filter { FileManager.default.fileExists(atPath: $0.path) }; files.insert(path); chunkStart = Date()
    }
    private func tick() {
        guard enabled, canListen() else { suspend(); return }
        recorder?.updateMeters()
        let now = Date.timeIntervalSinceReferenceDate
        let energy = (recorder?.averagePower(forChannel: 0) ?? -160) >= Float(threshold)
        if energy { latestEnergy = now }
        if engaged {
            // End turns using neural speech activity, not microphone loudness.
            // A fan or traffic must not keep resetting the reply timer.
            if now - clock.began >= 45 { finish(); return }
        }
        if Date().timeIntervalSince(chunkStart) >= (engaged ? 1.0 : 2.5) {
            recorder?.stop(); recorder = nil
            if let path = url {
                awaiting = true; send(["type": "chunk", "path": path.path, "generation": generation])
            }
            url = nil
            do { try beginChunk() } catch { status = error.localizedDescription; suspend() }
        }
    }
    private func finish() {
        finishing = true; timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        guard let path = url else { finishing = false; return }
        url = nil
        send(["type": "finish", "path": path.path, "generation": generation])
        status = "Transcribing the completed sentence locally…"
    }
    func suspend() {
        timer?.invalidate(); timer = nil; recorder?.stop(); recorder = nil
        if let url { try? FileManager.default.removeItem(at: url) }; url = nil
        generation = UUID().uuidString; awaiting = false; finishing = false; acknowledging = false
        if ready { send(["type": "reset", "awake": engaged, "language": recognitionLanguage, "generation": generation]) }
    }
    func shutdown() {
        suspend(); engaged = false; ready = false
        reader?.readabilityHandler = nil; try? writer?.close()
        if process?.isRunning == true { process?.terminate() }; process = nil
        for path in files { try? FileManager.default.removeItem(at: path) }; files.removeAll()
    }
}
