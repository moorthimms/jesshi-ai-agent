import Foundation
@main struct VoiceTimingTest {
    static func main() {
        var c = VoiceSilenceClock(); c.begin(at: 0); c.speech(at: 3)
        precondition(!c.shouldFinish(at: 3.9)); precondition(c.shouldFinish(at: 4))
        c.speech(at: 3.8); precondition(!c.shouldFinish(at: 4)); precondition(c.shouldFinish(at: 4.8))
        c.begin(at: 50); precondition(!c.shouldFinish(at: 100)); precondition(c.abandoned(at: 80))
        print("1-second silence, speech reset, and no-speech timeout passed")
    }
}
