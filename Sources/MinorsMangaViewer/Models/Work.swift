import Foundation

public struct Work: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let title: String
    public let author: Author
    public let versions: [WorkVersion]

    public var primaryVersion: WorkVersion? {
        versions.first
    }

    /// 返回第一个版本的文件夹路径（用于生成缩略图）
    public var primaryFolderURL: URL? {
        primaryVersion?.path
    }

    /// 返回第一个版本中解析出的刊号/集会名，用于作品浏览界面显示。
    public var publicationInfo: String? {
        primaryVersion?.parsed.publicationInfo
    }

    /// 判断该作品是否为单行本/合集类作品。
    public var isAnthology: Bool {
        primaryVersion?.parsed.isAnthology ?? false
    }

    /// 完整的显示标题，对单行本会把单行本标记和标题拼接起来。
    public var fullTitle: String {
        var parts: [String] = []
        if let creatorInfo = primaryVersion?.parsed.creatorInfo,
           primaryVersion?.parsed.isAnthology == true {
            parts.append("[\(creatorInfo)]")
        }
        if !title.isEmpty && title != "无题" {
            parts.append(title)
        }
        return parts.joined(separator: " ")
    }

    /// 用于排序的原始文件夹名称。优先使用第一个版本的原始文件夹名，
    /// 如果没有版本则回退到解析后的作品标题。
    var originalFolderName: String {
        primaryVersion?.name ?? title
    }
}
