import SwiftUI

struct FinderLikeGridView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @Binding var selectedWork: Work?
    var isReaderPresented: Bool
    var onOpenWork: (Work) -> Void
    @State private var gridWidth: CGFloat = 0
    @State private var keyMonitor: Any?

    private var navigableWorks: [Work] {
        libraryViewModel.separateAnthology ? normalWorks : libraryViewModel.filteredWorks
    }

    private var columnsCount: Int {
        let availableWidth = gridWidth - 2 * padding
        guard availableWidth > 0 else { return 1 }
        let count = Int(floor((availableWidth + spacing) / (itemMinWidth + spacing)))
        return max(1, count)
    }

    private let itemMinWidth: CGFloat = 140
    private let itemMaxWidth: CGFloat = 180
    private let spacing: CGFloat = 16
    private let padding: CGFloat = 16

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: itemMinWidth, maximum: itemMaxWidth), spacing: spacing)]
    }

    private var normalWorks: [Work] {
        libraryViewModel.filteredWorks.filter { !$0.isAnthology }
    }

    private var anthologyWorks: [Work] {
        libraryViewModel.filteredWorks.filter { $0.isAnthology }
    }

    var body: some View {
        Group {
            if libraryViewModel.separateAnthology {
                separatedBody
            } else {
                unifiedBody
            }
        }
        .onAppear {
            updateKeyMonitor()
        }
        .onChange(of: isReaderPresented) { _, _ in
            updateKeyMonitor()
        }
        .onChange(of: libraryViewModel.filteredWorks) { _, newValue in
            if selectedWork == nil || !newValue.contains(where: { $0.id == selectedWork?.id }) {
                selectedWork = newValue.first
            }
        }
        .onDisappear {
            stopKeyMonitor()
        }
    }

    private var unifiedBody: some View {
        ScrollView {
            if libraryViewModel.isLoading {
                ProgressView("加载中…")
                    .padding()
            } else if libraryViewModel.filteredWorks.isEmpty {
                ContentUnavailableView("没有作品", systemImage: "folder")
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(libraryViewModel.filteredWorks) { work in
                        gridItem(for: work, isWide: false)
                    }
                }
                .padding(padding)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { gridWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        gridWidth = newWidth
                    }
            }
        )
    }

    private var separatedBody: some View {
        ScrollView {
            VStack(spacing: 20) {
                if libraryViewModel.isLoading {
                    ProgressView("加载中…")
                        .padding()
                } else if libraryViewModel.filteredWorks.isEmpty {
                    ContentUnavailableView("没有作品", systemImage: "folder")
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(normalWorks) { work in
                            gridItem(for: work, isWide: false)
                        }
                    }
                    .padding(padding)

                    if !anthologyWorks.isEmpty {
                        anthologySection
                    }
                }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { gridWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        gridWidth = newWidth
                    }
            }
        )
    }

    private var anthologySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("单行本 / 合集")
                .font(.headline)
                .padding(.horizontal, padding)

            ScrollView(.horizontal) {
                HStack(spacing: spacing) {
                    ForEach(anthologyWorks) { work in
                        gridItem(for: work, isWide: true)
                            .frame(width: 330, height: 240)
                    }
                }
                .padding(.horizontal, padding)
            }
        }
    }

    private func gridItem(for work: Work, isWide: Bool) -> some View {
        WorkGridItem(work: work, isSelected: selectedWork?.id == work.id, isWide: isWide)
            .onTapGesture(count: 2) {
                selectedWork = work
                onOpenWork(work)
            }
            .onTapGesture {
                selectedWork = work
            }
            .contextMenu {
                Button("在 Finder 中显示") {
                    if let url = work.primaryFolderURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
    }

    private func updateKeyMonitor() {
        if isReaderPresented {
            stopKeyMonitor()
        } else {
            startKeyMonitor()
        }
    }

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let works = self.navigableWorks
            guard !works.isEmpty else { return event }

            let hasCommand = event.modifierFlags.contains(.command)

            // Command + 下方向键：打开当前选中的作品
            if hasCommand && event.keyCode == 125 {
                if let work = self.selectedWork {
                    self.onOpenWork(work)
                } else {
                    self.selectedWork = works[0]
                    self.onOpenWork(works[0])
                }
                return nil
            }

            let relevantModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            guard event.modifierFlags.intersection(relevantModifiers).isEmpty else { return event }

            let currentIndex: Int
            if let selected = self.selectedWork, let index = works.firstIndex(where: { $0.id == selected.id }) {
                currentIndex = index
            } else {
                self.selectedWork = works[0]
                return nil
            }

            let total = works.count
            var newIndex = currentIndex
            let columns = self.columnsCount

            switch event.keyCode {
            case 123: // left
                newIndex = currentIndex - 1
            case 124: // right
                newIndex = currentIndex + 1
            case 126: // up
                newIndex = currentIndex - columns
            case 125: // down
                newIndex = currentIndex + columns
            case 36: // return
                if let work = self.selectedWork {
                    self.onOpenWork(work)
                }
                return nil
            default:
                return event
            }

            let clamped = max(0, min(total - 1, newIndex))
            self.selectedWork = works[clamped]
            return nil
        }
    }

    private func stopKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
