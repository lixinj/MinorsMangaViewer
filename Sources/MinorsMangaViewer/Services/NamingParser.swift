import Foundation

public enum NamingParser {
    public static func parse(folderName: String) -> ParsedFolderName {
        let trimmed = folderName.trimmingCharacters(in: .whitespaces)
        var remaining = trimmed
        var prefix: String?
        var creatorInfo: String?
        var originalIP: String?
        var tags: [String] = []

        let parenPattern = #"\(([^)]*)\)"#
        let bracketPattern = #"\[([^\]]*)\]"#

        // 先提取方括号内容，避免方括号内的圆括号被当作 prefix/originalIP
        let brackets = extractMatches(pattern: bracketPattern, from: &remaining)
        let parens = extractMatches(pattern: parenPattern, from: &remaining)

        if let firstParen = parens.first {
            prefix = firstParen
        }
        if let firstBracket = brackets.first {
            creatorInfo = firstBracket
        }

        let nonTagBrackets = Array(brackets.dropFirst())
        tags.append(contentsOf: nonTagBrackets)

        if parens.count >= 2, let lastParen = parens.last {
            originalIP = lastParen
        }

        let title = remaining
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // 如果文件夹名只有方括号内容（如 [汉化组]），把它视为标签而非作者信息
        var finalCreatorInfo = creatorInfo
        var finalTags = tags
        let finalTitle = title
        if parens.isEmpty && title.isEmpty && tags.isEmpty, let info = creatorInfo {
            finalTags = [info]
            finalCreatorInfo = nil
        }

        return ParsedFolderName(
            raw: trimmed,
            prefix: prefix,
            creatorInfo: finalCreatorInfo,
            title: finalTitle.isEmpty ? "无题" : finalTitle,
            originalIP: originalIP,
            tags: finalTags
        )
    }

    private static func extractMatches(pattern: String, from string: inout String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        var matches: [String] = []
        var replacementRanges: [NSRange] = []

        regex.enumerateMatches(in: string, options: [], range: range) { result, _, _ in
            guard let result = result, result.numberOfRanges > 1 else { return }
            let matchRange = result.range(at: 1)
            if let swiftRange = Range(matchRange, in: string) {
                matches.append(String(string[swiftRange]))
                replacementRanges.append(result.range(at: 0))
            }
        }

        var mutable = string
        for r in replacementRanges.sorted(by: { $0.location > $1.location }) {
            if let range = Range(r, in: mutable) {
                mutable.replaceSubrange(range, with: " ")
            }
        }
        string = mutable

        return matches
    }
}
