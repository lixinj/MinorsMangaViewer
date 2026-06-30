import Darwin
import Foundation
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MinorsMangaViewer",
    category: "LibraryWatcher"
)

/// 监控漫画库文件夹变化，文件/文件夹增删改时通过 `onFilesChanged` 通知外部刷新。
@MainActor
final class LibraryWatcher {
    /// 受 `sourcesLock` 保护，以便 `nonisolated deinit` 可以安全取消而不用与 @MainActor 竞争。
    @ObservationIgnored
    private nonisolated(unsafe) var sources: [URL: (source: any DispatchSourceFileSystemObject, fd: Int32)] = [:]
    @ObservationIgnored
    private let sourcesLock = NSLock()

    private var watchedRoots: Set<URL> = []
    private let debounceInterval: TimeInterval = 2.0
    private var debounceWorkItem: DispatchWorkItem?

    /// 最大监控目录数，超过后只监控根目录，子目录变化通过完整重扫捕获。
    private let maxWatchedDirectories = 50

    var onFilesChanged: (() -> Void)?

    func watch(folder: URL) {
        guard !watchedRoots.contains(folder) else { return }
        watchedRoots.insert(folder)
        watchDirectoryRecursively(folder)
    }

    func unwatch(folder: URL) {
        watchedRoots.remove(folder)

        let folderPath = folder.standardizedFileURL.path
        let folderPathSlash = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        sourcesLock.lock()
        let keysToRemove = sources.keys.filter {
            let keyPath = $0.standardizedFileURL.path
            return keyPath == folderPath || keyPath.hasPrefix(folderPathSlash)
        }
        var removed: [any DispatchSourceFileSystemObject] = []
        for url in keysToRemove {
            if let entry = sources.removeValue(forKey: url) {
                removed.append(entry.source)
            }
        }
        sourcesLock.unlock()
        for source in removed {
            source.cancel()
        }
    }

    func unwatchAll() {
        sourcesLock.lock()
        let snapshot = sources.values.map(\.source)
        sources.removeAll()
        sourcesLock.unlock()
        for source in snapshot {
            source.cancel()
        }
        watchedRoots.removeAll()
    }

    private func watchDirectoryRecursively(_ url: URL) {
        watchDirectory(url)

        sourcesLock.lock()
        let currentCount = sources.count
        sourcesLock.unlock()
        guard currentCount < self.maxWatchedDirectories else {
            logger.info("FD limit reached (\(self.maxWatchedDirectories)); skipping subdirectory watchers for \(url.path)")
            return
        }

        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return }

        for case let subURL as URL in enumerator {
            sourcesLock.lock()
            let count = sources.count
            sourcesLock.unlock()
            if count >= self.maxWatchedDirectories {
                logger.info("FD limit reached (\(self.maxWatchedDirectories)); remaining subdirectories watched via rescan")
                break
            }
            guard
                let values = try? subURL.resourceValues(forKeys: [.isDirectoryKey]),
                values.isDirectory == true
            else { continue }
            watchDirectory(subURL)
        }
    }

    private func watchDirectory(_ url: URL) {
        sourcesLock.lock()
        let alreadyWatching = sources[url] != nil
        sourcesLock.unlock()
        guard !alreadyWatching else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.warning("Failed to open directory for watching: \(url.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sourcesLock.lock()
        sources[url] = (source, fd)
        sourcesLock.unlock()
    }

    private func handleChange() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.onFilesChanged?()
        }

        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    nonisolated deinit {
        sourcesLock.lock()
        let snapshot = sources.values.map(\.source)
        sources.removeAll()
        sourcesLock.unlock()
        for source in snapshot {
            source.cancel()
        }
    }
}
