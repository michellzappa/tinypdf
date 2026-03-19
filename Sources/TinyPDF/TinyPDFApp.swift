import SwiftUI
import AppKit
import TinyKit

// MARK: - FocusedValue key for per-window AppState

struct FocusedAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[FocusedAppStateKey.self] }
        set { self[FocusedAppStateKey.self] = newValue }
    }
}

// MARK: - App

@main
struct TinyPDFApp: App {
    @NSApplicationDelegateAdaptor(TinyAppDelegate.self) var appDelegate
    @FocusedValue(\.appState) private var activeState

    var body: some Scene {
        WindowGroup(id: "editor") {
            WindowContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                NewWindowButton()
            }

            CommandGroup(replacing: .appInfo) {
                Button("About TinyPDF") {
                    NSApp.orderFrontStandardAboutPanel()
                }
                Button("Welcome to TinyPDF") {
                    NotificationCenter.default.post(name: .showWelcome, object: nil)
                }
            }

            CommandGroup(after: .newItem) {
                OpenFileButton()

                OpenFolderButton()

                Divider()

                Button("Export as Markdown\u{2026}") {
                    activeState?.exportAsMarkdown()
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
    }
}

/// Each window owns its own AppState
struct WindowContentView: View {
    @State private var state = AppState()
    @State private var showWelcome = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        ContentView(state: state, columnVisibility: $columnVisibility)
            .navigationTitle(state.selectedFile?.lastPathComponent ?? "TinyPDF")
            .focusedSceneValue(\.appState, state)
            .onAppear {
                // Handle files passed via Finder before the window appeared
                if !TinyAppDelegate.pendingFiles.isEmpty {
                    let files = TinyAppDelegate.pendingFiles
                    TinyAppDelegate.pendingFiles.removeAll()
                    openFiles(files)
                } else if WelcomeState.isFirstLaunch {
                    showWelcome = true
                } else {
                    state.restoreLastFolder()
                }

                // Handle files opened after launch
                TinyAppDelegate.onOpenFiles = { [weak state] urls in
                    guard let state else { return }
                    openFilesInState(urls, state: state)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                withAnimation {
                    columnVisibility = columnVisibility == .detailOnly ? .automatic : .detailOnly
                }
            }
            .welcomeSheet(
                isPresented: $showWelcome,
                appName: "TinyPDF",
                subtitle: "A tiny PDF text extractor",
                features: [
                    ("folder", "Open a Folder", "Browse PDF files from the sidebar."),
                    ("doc.text.magnifyingglass", "Extract Text", "Instantly extract readable text from any PDF."),
                    ("rectangle.split.2x1", "PDF Preview", "Side-by-side extracted text and original PDF."),
                ],
                onOpen: { state.openFolder() },
                onDismiss: { state.restoreLastFolder() }
            )
            .background(WindowCloseGuard(state: state))
    }

    private func openFiles(_ urls: [URL]) {
        openFilesInState(urls, state: state)
    }

    private func openFilesInState(_ urls: [URL], state: AppState) {
        guard let url = urls.first else { return }
        let folder = url.deletingLastPathComponent()
        if state.folderURL != folder {
            state.setFolder(folder)
        }
        state.selectFile(url)
        columnVisibility = .detailOnly
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
}

// MARK: - Menu Buttons

/// Standalone button so @FocusedValue resolves reliably in menu context
struct OpenFileButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Open File\u{2026}") {
            state?.openFile()
        }
        .keyboardShortcut("o", modifiers: .command)
    }
}

struct OpenFolderButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Open Folder\u{2026}") {
            state?.openFolder()
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
    }
}

/// Button that uses @Environment to open a new window from the menu
struct NewWindowButton: View {
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button("New Window") {
            openWindow(id: "editor")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}
