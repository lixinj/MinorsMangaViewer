import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(appState.libraryURL?.path ?? "未选择")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("更改…") {
                        selectLibrary()
                    }
                }
            } header: {
                Text("漫画库目录")
            }

            Section {
                Button("清除缩略图缓存") {
                    ThumbnailCache.shared.clearMemoryCache()
                }
            } header: {
                Text("缓存")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 200)
        .padding()
    }

    private func selectLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择漫画库"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.libraryURL = url
    }
}
