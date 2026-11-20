import Foundation

/// The Korean deployment history shipped with the app, newest first.
enum ReleaseHistory {
    struct Entry: Identifiable, Equatable {
        let title: String
        let changes: [String]
        var id: String { title }
    }

    /// Copy of docs/releases/zip/00-Release History.txt; ReleaseHistoryTests keeps the two identical.
    static func bundledText() -> String? {
        guard let directory = AppResources.module.url(forResource: "ReleaseNotes", withExtension: nil) else { return nil }
        return try? String(contentsOf: directory.appendingPathComponent("Release History.txt"), encoding: .utf8)
    }

    static var bundled: [Entry] { bundledText().map(entries(from:)) ?? [] }

    /// Each block is a "YYYY-MM-DD (N차 배포)" title followed by "- change" lines.
    static func entries(from text: String) -> [Entry] {
        var result: [Entry] = []
        var title: String?
        var changes: [String] = []
        func flush() {
            if let title, !changes.isEmpty { result.append(Entry(title: title, changes: changes)) }
            title = nil
            changes = []
        }
        for line in text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            if line.range(of: #"^\d{4}-\d{2}-\d{2} \(\d+차 배포\)$"#, options: .regularExpression) != nil {
                flush()
                title = line
            } else if line.hasPrefix("- ") {
                changes.append(String(line.dropFirst(2)))
            } else if let last = changes.popLast() {
                // A wrapped change line continues the previous change.
                changes.append(last + " " + line)
            }
        }
        flush()
        return result
    }
}
