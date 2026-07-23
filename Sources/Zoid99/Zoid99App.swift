import SwiftUI

@main
struct Zoid99App: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if store.setupComplete {
                    MainShellView()
                } else {
                    FirstRunView()
                }
            }
            .environmentObject(store)
            .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("Research") {
                Button("Refresh Research") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("Open Today") { store.selectedDestination = .today }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Open Live Radar") { store.selectedDestination = .radar }
                    .keyboardShortcut("2", modifiers: [.command])
            }
        }
    }
}
