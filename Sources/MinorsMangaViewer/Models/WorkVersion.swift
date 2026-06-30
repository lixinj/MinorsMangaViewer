import Foundation

public struct WorkVersion: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let path: URL
    public let type: FolderType
    public let parsed: ParsedFolderName

    private static let tagKeywords = [
        "無修正", "dl版", "漢化", "汉化", "mjk-", "t-", "z-", "个人", "組", "组",
        "fakku", "faaku", "無毒", "heart♡", "不想記名", "黑条", "中扫", "后期",
        "整合版", "重嵌", "重翻", "修正", "彩字", "中国翻訳", "中国翻译"
    ]

    /// 返回从标签或创作者信息中提取的可读标签摘要（不含 "原版" 默认值）
    public var tagSummary: String {
        var parts = parsed.tags
        if let creator = parsed.creatorInfo, looksLikeTag(creator) {
            parts.insert(creator, at: 0)
        }
        guard !parts.isEmpty else { return "" }
        return parts.joined(separator: " / ")
    }

    public var displayName: String {
        parsed.displayTitle
    }

    /// 生成在版本选择器中的显示标签
    ///
    /// 优先级：
    /// 1. 有可识别的标签（汉化组/無修正等）→ 显示标签
    /// 2. 标题为英文 → "英版"
    /// 3. 解析出的标题与作品名不同 → 使用解析标题
    /// 4. 其他 → "原版"
    public func displayLabel(relativeTo workTitle: String) -> String {
        // 1. 有可识别的标签 → 显示标签
        let significantTags = parsed.tags.filter { !$0.isEmpty }
        if !significantTags.isEmpty {
            return significantTags.joined(separator: " / ")
        }
        if let creator = parsed.creatorInfo, looksLikeTag(creator) {
            return creator
        }

        let title = parsed.displayTitle

        // 2. 标题为英文 → "英版"
        if !title.isEmpty && title != name && isEnglish(title) {
            return "英版"
        }

        // 3. 解析标题与作品名不同 → 使用解析标题
        if !title.isEmpty && title != workTitle && title != name {
            return title
        }

        // 4. 默认
        return "原版"
    }

    private func isEnglish(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let allowed: CharacterSet = .letters.union(.whitespaces).union(.punctuationCharacters).union(.decimalDigits)
        for scalar in trimmed.unicodeScalars {
            if !allowed.contains(scalar) {
                return false
            }
        }
        let letters = trimmed.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        return letters.allSatisfy { $0.isASCII }
    }

    private func looksLikeTag(_ string: String) -> Bool {
        let lower = string.lowercased()
        return Self.tagKeywords.contains { lower.contains($0) }
    }
}
