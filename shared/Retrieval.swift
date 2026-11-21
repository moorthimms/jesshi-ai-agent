import Foundation
func retrievedExcerpt(_ text: String, query: String, limit: Int = 8000) -> String {
    let chars = Array(text)
    let words = query.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count >= 3 }
    let chunks = stride(from: 0, to: chars.count, by: 1600).map { index -> (Int, String, Int) in
        let chunk = String(chars[index..<min(index + 1600, chars.count)])
        let lower = chunk.lowercased()
        return (index / 1600 + 1, chunk, words.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) })
    }
    let best = chunks.sorted { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 > $1.2 }.prefix(4).sorted { $0.0 < $1.0 }
    return String(best.map { "[Excerpt \($0.0)] \($0.1)" }.joined(separator: "\n").prefix(limit))
}
