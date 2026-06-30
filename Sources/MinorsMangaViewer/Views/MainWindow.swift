import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @State private var selectedWork: Work?
    @State private var isReaderPresented = false
    @State private var showingFilterPopover = false
    @State private var filterText = ""
    @State private var readerWorks: [Work] = []
    @State private var readerIndex: Int = 0

    var body: some View {
        NavigationSplitView {
            SidebarView(isReaderPresented: $isReaderPresented)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 400)
        } detail: {
            FinderLikeGridView(selectedWork: $selectedWork, isReaderPresented: isReaderPresented, onOpenWork: openReader)
                .navigationSplitViewColumnWidth(min: 400, ideal: 700, max: .infinity)
        }
        .toolbar(isReaderPresented ? .hidden : .visible)
        .toolbar {
            ToolbarItem(placement: .principal) {
                pathView
            }
            ToolbarItem {
                Button("选择库目录") {
                    selectLibrary()
                }
            }
            ToolbarItem {
                Button("刷新") {
                    Task {
                        if let url = appState.libraryURL {
                            await libraryViewModel.loadLibrary(url: url)
                        }
                    }
                }
            }
            ToolbarItem {
                Button {
                    filterText = libraryViewModel.filenameFilters.joined(separator: "\n")
                    showingFilterPopover = true
                } label: {
                    Label("过滤", systemImage: "line.3.horizontal.decrease.circle")
                }
                .help("过滤阅读器中的图片文件")
                .popover(isPresented: $showingFilterPopover) {
                    filterPopover
                }
            }
            ToolbarItem {
                Button {
                    libraryViewModel.separateAnthology.toggle()
                } label: {
                    Image(systemName: libraryViewModel.separateAnthology ? "rectangle.split.2x1" : "square.grid.2x2")
                }
                .help(libraryViewModel.separateAnthology ? "统一显示所有作品" : "分离显示单行本")
            }
        }
        .overlay {
            if isReaderPresented, let work = selectedWork {
                ReaderView(
                    work: work,
                    works: readerWorks,
                    currentIndex: readerIndex,
                    onClose: { isReaderPresented = false },
                    onOpenWork: { newWork, newIndex in
                        selectedWork = newWork
                        readerIndex = newIndex
                    },
                    filenameFilters: libraryViewModel.filenameFilters
                )
                .id(work.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .task {
            if let url = appState.libraryURL {
                await libraryViewModel.loadLibrary(url: url)
            }
        }
    }

    private var pathView: some View {
        HStack(spacing: 6) {
            ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                Text(component)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(index == pathComponents.count - 1 ? .primary : .secondary)

                if index < pathComponents.count - 1 {
                    Image(systemName: "chevron.compact.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
        )
    }

    private var pathComponents: [String] {
        guard let libraryURL = appState.libraryURL else { return [] }
        var components = [libraryURL.lastPathComponent]
        if let author = libraryViewModel.selectedAuthor {
            components.append(author.name)
            if let collection = libraryViewModel.selectedCollection, !collection.name.isEmpty {
                components.append(collection.displayName)
            }
        }
        return components
    }

    private var filterPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("过滤图片")
                .font(.headline)

            Text("输入要完全排除的文件名或文件夹名，每行一个或逗号分隔：")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $filterText)
                .font(.body.monospaced())
                .frame(width: 280, height: 120)
                .border(Color.secondary.opacity(0.2), width: 1)

            HStack {
                Spacer()
                Button("取消") {
                    showingFilterPopover = false
                }
                Button("应用") {
                    applyFilters()
                    showingFilterPopover = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func applyFilters() {
        let separators = CharacterSet(charactersIn: ",，\n")
        let filters = filterText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .init(charactersIn: "\r")) }
            .filter { !$0.isEmpty }
        libraryViewModel.filenameFilters = filters
    }

    private func selectLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择漫画库"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.libraryURL = url
        Task {
            await libraryViewModel.loadLibrary(url: url)
        }
    }

    private func openReader(work: Work) {
        let works = libraryViewModel.filteredWorks
        readerWorks = works
        readerIndex = works.firstIndex(where: { $0.id == work.id }) ?? 0
        selectedWork = work
        isReaderPresented = true
    }
}
