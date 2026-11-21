import Foundation
import CryptoKit
import CommonCrypto

struct PortableChat: Codable { var role: String; var content: String }
struct PortableDocument: Codable, Identifiable { var id: String; var name: String; var text: String }
struct PortableTask: Codable, Identifiable { var id: String; var title: String; var done: Bool; var due: Double? }
struct PortableRoutine: Codable, Identifiable { var id: String; var name: String; var prompt: String }
struct PortableState: Codable {
    var version = 1
    var chats: [PortableChat] = []
    var documents: [PortableDocument] = []
    var memory = ""
    var notes = ""
    var tasks: [PortableTask] = []
    var routines: [PortableRoutine] = []
    var activity: [String] = []
    var language = "English"
    var lowPower = false
    var fontSize = 16.0
    var voice = false
    func validated() throws -> PortableState {
        guard version == 1, chats.count <= 5000, documents.count <= 5000,
              tasks.count <= 5000, routines.count <= 5000, activity.count <= 5000,
              chats.allSatisfy({ ["user", "assistant"].contains($0.role) }),
              documents.allSatisfy({ $0.text.count <= 120000 }),
              tasks.allSatisfy({ $0.due?.isFinite ?? true }) else { throw BackupError.invalid }
        return self
    }
}
enum BackupError: LocalizedError {
    case password, invalid
    var errorDescription: String? { self == .password ? "Use a password with at least 12 characters." : "Invalid backup, incorrect password, or damaged data." }
}
struct EncryptedBackup: Codable { var format: String; var salt: String; var iv: String; var data: String }
enum BackupCrypto {
    static func derive(_ password: String, salt: Data) throws -> SymmetricKey {
        guard password.count >= 12 else { throw BackupError.password }
        var derived = [UInt8](repeating: 0, count: 32)
        let pass = Array(password.utf8)
        let result = pass.withUnsafeBytes { p in salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress?.assumingMemoryBound(to: Int8.self), pass.count,
                s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 250000, &derived, 32)
        }}
        guard result == kCCSuccess else { throw BackupError.invalid }
        return SymmetricKey(data: derived)
    }
    static func seal(_ state: PortableState, password: String) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw BackupError.invalid }
        let salt = Data(bytes), key = try derive(password, salt: salt)
        let sealed = try AES.GCM.seal(JSONEncoder().encode(state), using: key)
        return try JSONEncoder().encode(EncryptedBackup(format: "jessy-encrypted-v1", salt: salt.base64EncodedString(), iv: Data(sealed.nonce).base64EncodedString(), data: (sealed.ciphertext + sealed.tag).base64EncodedString()))
    }
    static func open(_ data: Data, password: String) throws -> PortableState {
        guard data.count <= 20_000_000 else { throw BackupError.invalid }
        let envelope = try JSONDecoder().decode(EncryptedBackup.self, from: data)
        guard envelope.format == "jessy-encrypted-v1", let salt = Data(base64Encoded: envelope.salt), salt.count == 16,
              let iv = Data(base64Encoded: envelope.iv), iv.count == 12,
              let payload = Data(base64Encoded: envelope.data), payload.count >= 16 else { throw BackupError.invalid }
        let key = try derive(password, salt: salt)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: payload.dropLast(16), tag: payload.suffix(16))
        return try JSONDecoder().decode(PortableState.self, from: AES.GCM.open(box, using: key)).validated()
    }
}
