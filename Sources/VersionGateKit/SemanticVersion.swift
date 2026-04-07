import Foundation

/// Lightweight semantic version value type used by `VersionGateManager`.
///
/// Parses strings like `"1.2.10"` into a comparable struct so that
/// `"1.2.10" > "1.2.9"` evaluates correctly (lexicographic string comparison
/// would produce the wrong answer).
public struct SemanticVersion: Comparable, Equatable {
    public let components: [Int]

    public init(major: Int, minor: Int = 0, patch: Int = 0, build: Int = 0) {
        self.components = [major, minor, patch, build]
    }

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ".")
        guard !parts.isEmpty, parts.count <= 4 else { return nil }

        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            parsed.append(value)
        }
        // Pad to 4 components so comparisons are consistent.
        while parsed.count < 4 {
            parsed.append(0)
        }
        self.components = parsed
    }

    public static let zero = SemanticVersion(major: 0, minor: 0, patch: 0, build: 0)

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        for i in 0..<max(lhs.components.count, rhs.components.count) {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        for i in 0..<max(lhs.components.count, rhs.components.count) {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return false }
        }
        return true
    }
}
