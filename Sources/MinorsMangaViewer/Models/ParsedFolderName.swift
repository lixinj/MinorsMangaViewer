import Foundation

public struct ParsedFolderName: Hashable, Sendable {
    public let raw: String
    public let prefix: String?
    public let creatorInfo: String?
    public let title: String
    public let originalIP: String?
    public let tags: [String]
}

extension ParsedFolderName {
    public var displayTitle: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    public var tagSummary: String {
        tags.joined(separator: " / ")
    }

    /// 提取文件夹名中的刊号/集会名，例如 "(COMIC 夢幻転生 2023年9月号)" → "(COMIC 夢幻転生 2023年9月号)"
    public var publicationInfo: String? {
        let pattern = #"\((COMIC\s+[^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: raw, options: [], range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range(at: 0), in: raw) else {
            return nil
        }
        return String(raw[range])
    }

    /// 判断该文件夹名是否标记为单行本/合集类作品。
    public var isAnthology: Bool {
        let markers = ["单行本", "合集", "总集篇", "anthology", "collection"]
        let candidates = [prefix, creatorInfo].compactMap { $0 } + tags
        return candidates.contains { candidate in
            let lower = candidate.lowercased()
            return markers.contains { lower.contains($0) }
        }
    }
}
