import Foundation
import SwiftUI

enum ReaderLayout: String, CaseIterable {
    case single = "单页"
    case doubleRightToLeft = "右开"
    case doubleLeftToRight = "左开"
}

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published var work: Work
    @Published var currentVersion: WorkVersion
    @Published var imageURLs: [URL] = []
    @Published var currentPageIndex: Int = 0
    @Published var layout: ReaderLayout
    @Published var isLoading = false
    @Published var filenameFilters: [String] = []

    private let progressStore = ReadingProgressStore.shared
    @Published private var imageCache: [Int: NSImage] = [:]

    private var pageProvider: (any PageProvider)?
    private(set) var isArchiveVersion: Bool = false

    /// 项目内嵌的空白页源文件 URL。
    static func blankPageSourceURL() -> URL? {
        Bundle.module.url(forResource: "blank_page", withExtension: "jpg")
    }

    /// 在指定图片之前插入一张空白页图片到源文件夹。
    /// 空白页文件名会在原文件名后追加一个空格，使其排序紧邻原图之前。
    /// 仅支持文件夹版本，压缩包版本会抛出错误。
    func insertBlankPage(before targetURL: URL) async throws {
        guard !isArchiveVersion else {
            throw InsertBlankPageError.archiveNotSupported
        }
        guard let sourceURL = Self.blankPageSourceURL() else {
            throw InsertBlankPageError.missingSourceImage
        }

        let directory = targetURL.deletingLastPathComponent()
        let originalName = targetURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let targetLastComponent = targetURL.lastPathComponent

        // 生成目标文件名：原文件名 + 空格 + .ext
        // 扩展名保持与项目内嵌空白页源文件一致（jpg），避免格式不一致
        // 若已存在，则递增空格数量直到可用
        var destinationURL = directory.appendingPathComponent(originalName + " ." + ext)
        var spaceCount = 1
        while FileManager.default.fileExists(atPath: destinationURL.path) {
            spaceCount += 1
            let spaces = String(repeating: " ", count: spaceCount)
            destinationURL = directory.appendingPathComponent(originalName + spaces + "." + ext)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        // 重新加载当前版本，保留大致阅读位置
        await loadVersion(currentVersion, preservingPage: true)

        // 将当前页定位到空白页位置，使空白页和原图并排显示
        if let newIndex = imageURLs.firstIndex(where: { $0.lastPathComponent == targetLastComponent }) {
            let blankPageIndex = max(0, newIndex - 1)
            // 预加载空白页图片，确保双页显示逻辑能正确判断其为竖图
            if blankPageIndex < imageURLs.count,
               cachedImage(at: blankPageIndex) == nil,
               let image = await loadImage(at: blankPageIndex) {
                setCachedImage(image, at: blankPageIndex)
            }
            currentPageIndex = blankPageIndex
            saveProgress()
            preloadAroundCurrentPage()
        }
    }

    func cachedImage(at index: Int) -> NSImage? {
        imageCache[index]
    }

    func setCachedImage(_ image: NSImage?, at index: Int) {
        imageCache[index] = image
    }

    /// 异步加载指定索引的图片。会优先使用缓存，然后根据版本类型从文件夹或压缩包读取。
    func loadImage(at index: Int) async -> NSImage? {
        guard index >= 0, index < imageURLs.count else { return nil }
        if let cached = cachedImage(at: index) {
            return cached
        }

        do {
            let image = try await pageProvider?.image(at: index)
                ?? NSImage(contentsOf: imageURLs[index])
            if let image = image {
                setCachedImage(image, at: index)
            }
            return image
        } catch {
            return nil
        }
    }

    /// 判断图片是否为竖图（高大于宽）。使用图片表示的像素尺寸，比 NSImage.size 更可靠。
    /// 若图片尚未缓存，按横图处理。
    func isPortrait(at index: Int) -> Bool {
        guard let image = cachedImage(at: index) else { return false }
        if let representation = image.representations.first {
            return representation.pixelsHigh > representation.pixelsWide
        }
        return image.size.height > image.size.width
    }

    /// 返回当前视图应该显示的图片索引范围。
    /// 单页模式始终只显示一页；双页模式下：
    /// - 第一页默认单独显示
    /// - 横图（长小于宽）单独显示
    /// - 竖图（长大于宽）若下一张也是竖图则两张并排，否则单独显示
    var currentPageRange: Range<Int> {
        guard !imageURLs.isEmpty else { return 0..<0 }
        guard layout != .single else {
            return currentPageIndex..<(currentPageIndex + 1)
        }

        if currentPageIndex == 0 {
            return 0..<1
        }

        if !isPortrait(at: currentPageIndex) {
            // 横图单独显示
            return currentPageIndex..<(currentPageIndex + 1)
        }

        // 竖图：下一张也是竖图才并排
        if currentPageIndex + 1 < imageURLs.count,
           isPortrait(at: currentPageIndex + 1) {
            return currentPageIndex..<(currentPageIndex + 2)
        }

        return currentPageIndex..<(currentPageIndex + 1)
    }

    /// 预加载当前页前后几页的图片，减少翻页时的黑屏闪烁。
    func preloadAroundCurrentPage(window: Int = 3) {
        guard !imageURLs.isEmpty else { return }
        let start = max(0, currentPageIndex - window)
        let end = min(imageURLs.count - 1, currentPageIndex + window + (layout == .single ? 0 : 1))

        for i in start...end {
            guard cachedImage(at: i) == nil else { continue }
            Task(priority: .background) { [weak self] in
                _ = await self?.loadImage(at: i)
            }
        }
    }

    var currentPageDisplay: String {
        let total = imageURLs.count
        guard total > 0 else { return "0 / 0" }
        let range = currentPageRange
        let first = range.lowerBound + 1
        let last = range.upperBound
        if last - range.lowerBound == 1 {
            return "\(first) / \(total)"
        } else {
            return "\(first) - \(last) / \(total)"
        }
    }

    var canGoNext: Bool {
        currentPageRange.upperBound < imageURLs.count
    }

    var canGoPrevious: Bool {
        currentPageIndex > 0
    }

    init(work: Work, version: WorkVersion, layout: ReaderLayout, filenameFilters: [String] = []) {
        self.work = work
        self.currentVersion = version
        self.layout = layout
        self.filenameFilters = filenameFilters
    }

    func loadVersion(_ version: WorkVersion, preservingPage: Bool = true) async {
        isLoading = true
        defer { isLoading = false }

        let previousPage = currentPageIndex
        currentVersion = version
        progressStore.set(versionID: version.id.uuidString, for: work.id.uuidString)

        // 关闭旧的 provider，清理临时目录
        pageProvider?.close()
        pageProvider = nil
        imageCache.removeAll()

        do {
            let provider = try await ArchiveService.provider(for: version.path)
            pageProvider = provider
            isArchiveVersion = version.isArchive

            // 生成页面标识 URL：文件夹用真实路径，压缩包用虚拟路径
            let count = provider.pageCount
            if version.isArchive {
                imageURLs = (0..<count).map { version.path.appendingPathComponent("__page__\($0)") }
            } else {
                let allURLs = try await FolderScanner.imageFiles(in: version.path)
                imageURLs = allURLs.filter { url in
                    !filenameFilters.contains { filter in
                        guard !filter.isEmpty else { return false }
                        if url.lastPathComponent == filter { return true }
                        return url.pathComponents.contains(filter)
                    }
                }
            }

            if preservingPage {
                if previousPage < imageURLs.count {
                    currentPageIndex = previousPage
                } else if imageURLs.isEmpty {
                    currentPageIndex = 0
                } else {
                    currentPageIndex = imageURLs.count - 1
                }
            } else {
                currentPageIndex = 0
            }
            preloadAroundCurrentPage()
        } catch {
            imageURLs = []
            currentPageIndex = 0
            isArchiveVersion = false
        }
    }

    func nextPage() {
        guard canGoNext else { return }
        if layout == .single {
            currentPageIndex += 1
        } else {
            if cachedImage(at: currentPageIndex) == nil {
                // 图片尚未缓存，保守地只前进一页，避免跳过竖图
                currentPageIndex += 1
            } else {
                currentPageIndex = currentPageRange.upperBound
            }
        }
        saveProgress()
        preloadAroundCurrentPage()
    }

    func previousPage() {
        guard canGoPrevious else { return }
        if layout == .single {
            currentPageIndex -= 1
        } else {
            currentPageIndex = previousGroupStart(from: currentPageRange.lowerBound)
        }
        saveProgress()
        preloadAroundCurrentPage()
    }

    /// 根据当前组起始页，计算上一组的起始页，保持双页浏览顺序。
    /// - 上一组若只有一页，返回该页索引。
    /// - 上一组若为双页（两张竖图），返回双页中第一页的索引。
    /// - 第一页始终单独显示，因此回到第一页时返回 0。
    private func previousGroupStart(from startIndex: Int) -> Int {
        guard startIndex > 0 else { return 0 }

        let previousEnd = startIndex - 1
        if previousEnd == 0 {
            return 0
        }

        if isPortrait(at: previousEnd),
           previousEnd - 1 >= 1,
           isPortrait(at: previousEnd - 1) {
            return previousEnd - 1
        }

        return previousEnd
    }

    func goToPage(_ index: Int) {
        currentPageIndex = max(0, min(index, imageURLs.count - 1))
        saveProgress()
        preloadAroundCurrentPage()
    }

    /// 双页模式下把当前显示的两页整体向后偏移一页，用于手动重新对齐跨页。
    func shiftDoublePageForward() {
        guard layout != .single, currentPageIndex < imageURLs.count - 1 else { return }
        currentPageIndex += 1
        saveProgress()
        preloadAroundCurrentPage()
    }

    private func saveProgress() {
        progressStore.set(versionID: currentVersion.id.uuidString, for: work.id.uuidString)
    }

    deinit {
        pageProvider?.close()
    }
}

enum ReaderLayoutStore {
    private static let key = "readerLayout"

    static func load() -> ReaderLayout {
        guard let rawValue = UserDefaults.standard.string(forKey: key),
              let layout = ReaderLayout(rawValue: rawValue) else {
            return .single
        }
        return layout
    }

    static func save(_ layout: ReaderLayout) {
        UserDefaults.standard.set(layout.rawValue, forKey: key)
    }
}

enum InsertBlankPageError: Error, LocalizedError {
    case missingSourceImage
    case archiveNotSupported

    var errorDescription: String? {
        switch self {
        case .missingSourceImage:
            return "未找到项目内嵌的空白页图片。"
        case .archiveNotSupported:
            return "压缩包版本不支持插入空白页。"
        }
    }
}
