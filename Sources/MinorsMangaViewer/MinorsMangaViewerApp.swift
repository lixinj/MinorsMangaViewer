import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            guard let window = NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first,
                  let screen = window.screen else { return }
            window.setFrame(screen.visibleFrame, display: true, animate: false)
            window.title = ""
        }
    }
}

@main
struct MinorsMangaViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var libraryViewModel: LibraryViewModel
    @Environment(\.openWindow) private var openWindow

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        _libraryViewModel = StateObject(wrappedValue: LibraryViewModel(appState: state))
        if let path = Self.diagnosePath() {
            Self.runDiagnose(path: path)
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindow()
                .environmentObject(appState)
                .environmentObject(libraryViewModel)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建主窗口") {
                    openWindow(id: "main")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(appState)
        }
    }

    private static func diagnosePath() -> String? {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--diagnose"), index + 1 < args.count {
            return args[index + 1]
        }
        return nil
    }

    private static func runDiagnose(path: String) {
        let url = URL(fileURLWithPath: path)

        Task {
            do {
                let authors = try await FolderScanner.scan(libraryURL: url)
                print("扫描到 \(authors.count) 个作者/顶层目录")

                for author in authors {
                    print("\n=== 作者: \(author.name) ===")
                    let collections = try await FolderScanner.collections(for: author)
                    print("分类数量: \(collections.count)")

                    for collection in collections {
                        print("\n  [分类] \(collection.displayName) — \(collection.works.count) 个作品")
                        for work in collection.works {
                            print("\n    [作品] \(work.title)")
                            for version in work.versions {
                                print("      - \(version.displayLabel(relativeTo: work.title)) -> \(version.path.lastPathComponent)")
                            }
                        }
                    }
                }
            } catch {
                print("扫描失败: \(error)")
            }
            exit(0)
        }

        RunLoop.main.run()
    }
}
