import Foundation

@MainActor
public enum FolderScanner {
    /// 扫描时要跳过的文件夹名集合（大小写不敏感、完全匹配）。
    public static var skippedFolderNames: Set<String> = ["lib"]

    private static func shouldSkipFolder(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return skippedFolderNames.contains { $0.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    public static func scan(libraryURL: URL) async throws -> [Author] {
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        let urls = try FileManager.default
            .contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .filter { !shouldSkipFolder($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        // 如果库根目录下的每个子目录都直接包含图片文件，说明用户选择的是“作者目录”本身，
        // 而不是“库根目录”。此时把 libraryURL 本身视为一个作者，子目录作为其作品。
        let allSubfoldersAreWorks = urls.allSatisfy { containsImageFiles($0) }
        if !urls.isEmpty && allSubfoldersAreWorks {
            return [Author(name: libraryURL.lastPathComponent, path: libraryURL)]
        }

        // 只有当库根目录下所有顶层目录都是分类文件夹（如 Manga、Doujinshi）时，
        // 才把整个根目录视为一个作者。否则每个顶层目录都应作为独立作者展示，
        // 避免普通作者目录被根目录误吞。
        let allCategories = urls.allSatisfy { isCategoryFolder($0) }
        if !urls.isEmpty && allCategories {
            return [Author(name: libraryURL.lastPathComponent, path: libraryURL)]
        }

        return urls.map { Author(name: $0.lastPathComponent, path: $0) }
    }

    public static func works(for author: Author) async throws -> [Work] {
        let collections = try await Self.collections(for: author)
        return collections.flatMap { $0.works }.sorted { $0.title < $1.title }
    }

    public static func collections(for author: Author) async throws -> [WorkCollection] {
        let topLevelURLs = try contentsOfDirectoryIncludingArchives(at: author.path)
        var collections: [WorkCollection] = []
        var rootWorks: [Work] = []

        for url in topLevelURLs {
            if isCategoryFolder(url) {
                let folderType = FolderType.from(folderName: url.lastPathComponent)
                let works = try await Self.scanWorks(inCategory: url, author: author)
                collections.append(WorkCollection(
                    name: sanitizedName(of: url),
                    path: url,
                    folderType: folderType,
                    works: mergeWorks(works).sorted { $0.originalFolderName < $1.originalFolderName }
                ))
            } else if let work = try await work(fromContainer: url, author: author, type: .unknown) {
                rootWorks.append(work)
            }
        }

        if !rootWorks.isEmpty {
            collections.insert(WorkCollection(
                name: "",
                path: author.path,
                folderType: .unknown,
                works: mergeWorks(rootWorks).sorted { $0.originalFolderName < $1.originalFolderName }
            ), at: 0)
        }

        return collections
    }

    private static func mergeWorks(_ works: [Work]) -> [Work] {
        let grouped = Dictionary(grouping: works) { work in
            let publication = work.primaryVersion?.parsed.publicationInfo ?? ""
            return normalize(title: work.title) + "|" + normalize(title: publication)
        }
        return grouped.map { (_, group) in
            let title = group.first?.title ?? ""
            let author = group.first?.author ?? Author(name: "", path: URL(fileURLWithPath: "/"))
            let allVersions = group.flatMap { $0.versions }
            return Work(title: title, author: author, versions: allVersions)
        }
    }

    private static func normalize(title: String) -> String {
        title
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }

    public static func scanWorks(inCategory categoryURL: URL, author: Author) async throws -> [Work] {
        let folderType = FolderType.from(folderName: categoryURL.lastPathComponent)
        let urls = try contentsOfDirectoryIncludingArchives(at: categoryURL)
        var works: [Work] = []

        for url in urls {
            if isSubcategoryFolder(url) {
                works.append(contentsOf: try await Self.scanWorks(inCategory: url, author: author))
            } else if let work = try await work(fromContainer: url, author: author, type: folderType) {
                works.append(work)
            }
        }

        return works
    }

    public static func work(fromContainer url: URL, author: Author, type: FolderType) async throws -> Work? {
        let containerName = sanitizedName(of: url)
        let parsed = NamingParser.parse(folderName: containerName)

        var versions: [WorkVersion] = []

        // 压缩包文件直接作为一个版本
        if ArchiveService.isArchive(url) {
            versions.append(WorkVersion(
                name: containerName,
                path: url,
                type: type,
                parsed: parsed
            ))
        } else {
            await collectVersions(in: url, depth: 0, into: &versions, type: type)
        }

        guard !versions.isEmpty else { return nil }

        let title = bestTitle(for: parsed, versions: versions, fallback: containerName)
        return Work(title: title, author: author, versions: versions)
    }

    private static func collectVersions(in url: URL, depth: Int, into versions: inout [WorkVersion], type: FolderType) async {
        guard depth < 4 else { return }
        let name = sanitizedName(of: url)

        // 压缩包文件直接作为一个版本
        if ArchiveService.isArchive(url) {
            versions.append(WorkVersion(
                name: name,
                path: url,
                type: type,
                parsed: NamingParser.parse(folderName: name)
            ))
            return
        }

        let folderName = name
        let hasImages: Bool
        do {
            hasImages = !(try await imageFiles(in: url).isEmpty)
        } catch {
            hasImages = false
        }

        if hasImages {
            versions.append(WorkVersion(
                name: folderName,
                path: url,
                type: type,
                parsed: NamingParser.parse(folderName: folderName)
            ))
        }

        guard let subitems = try? contentsOfDirectoryIncludingArchives(at: url) else { return }
        for subitem in subitems {
            await collectVersions(in: subitem, depth: depth + 1, into: &versions, type: type)
        }
    }

    public static func imageFiles(in folder: URL) async throws -> [URL] {
        let extensions = Set(["jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic"])
        let urls = try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { url in
                extensions.contains(url.pathExtension.lowercased())
            }
            .sorted { naturalCompare($0.lastPathComponent, $1.lastPathComponent) }
        return urls
    }

    // MARK: - Helpers

    private static func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !shouldSkipFolder($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 返回目录下的子文件夹和压缩包文件，用于版本递归收集。
    private static func contentsOfDirectoryIncludingArchives(at url: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { item in
                if ArchiveService.isArchive(item) { return true }
                guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey]) else { return false }
                return values.isDirectory == true
            }
            .filter { !shouldSkipFolder($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func sanitizedName(of url: URL) -> String {
        url.lastPathComponent.trimmingCharacters(in: .whitespaces)
    }

    private static func isCategoryFolder(_ url: URL) -> Bool {
        let name = sanitizedName(of: url).lowercased()
        let categoryPrefixes = ["manga", "doujinshi", "doujin", "lib", "comic", "collection", "works"]
        if categoryPrefixes.contains(where: { name.hasPrefix($0) }) {
            return true
        }
        if name.range(of: #"^\d{4}\s*-\s*\d{4}$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func isSubcategoryFolder(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let socialKeywords = ["pixiv", "twitter", "fanbox", "fantia", "patreon"]
        return socialKeywords.contains(where: { name.contains($0) })
    }

    private static func containsImageFiles(_ url: URL) -> Bool {
        let extensions = Set(["jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic"])
        guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return false
        }
        return urls.contains { extensions.contains($0.pathExtension.lowercased()) }
    }

    private static func bestTitle(for parsed: ParsedFolderName, versions: [WorkVersion], fallback: String) -> String {
        let title: String
        if !parsed.displayTitle.isEmpty {
            title = parsed.displayTitle
        } else if let firstNonEmpty = versions.first(where: { !$0.parsed.displayTitle.isEmpty }) {
            title = firstNonEmpty.parsed.displayTitle
        } else {
            title = fallback
        }
        return title.trimmingCharacters(in: .whitespaces)
    }

    private static func naturalCompare(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.numeric, .caseInsensitive, .widthInsensitive]) == .orderedAscending
    }
}
