import Foundation
@main struct BackupInterop {
    static func main() throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1]), output = URL(fileURLWithPath: CommandLine.arguments[2])
        let state = try BackupCrypto.open(Data(contentsOf: input), password: "jessy interoperability test")
        precondition(state.memory == "Portable memory ✓")
        try BackupCrypto.seal(state, password: "jessy interoperability test").write(to: output)
        precondition(retrievedExcerpt(String(repeating: "a", count: 6000) + " BLUEFIN project", query: "BLUEFIN").contains("BLUEFIN"))
        print("Swift backup decrypt/encrypt and retrieval passed")
    }
}
