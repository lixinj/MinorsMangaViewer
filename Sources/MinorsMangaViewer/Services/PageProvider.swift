import AppKit
import Foundation

/// 统一的页面来源抽象。
///
/// 实现者可以是本地文件夹、ZIP/CBZ 压缩包、RAR/CBR 压缩包等。
/// 阅读器通过此协议按索引获取页面图片，无需关心底层存储。
protocol PageProvider: Sendable {
    /// 总页数
    var pageCount: Int { get }

    /// 获取指定索引的页面图片。
    func image(at index: Int) async throws -> NSImage

    /// 释放资源。对于压缩包实现，通常需要清理临时解压目录。
    func close()
}

enum PageProviderError: Error {
    case indexOutOfRange
    case imageLoadFailed
}

func naturalPageCompare(_ lhs: String, _ rhs: String) -> Bool {
    lhs.compare(rhs, options: [.numeric, .caseInsensitive, .widthInsensitive]) == .orderedAscending
}
