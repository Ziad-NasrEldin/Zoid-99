import SwiftUI
import UserNotifications

@main
struct Zoid99App: App {
    @StateObject private var store: AppStore

    init() {
        let isPackagedApplication = Bundle.main.bundleURL.pathExtension == "app"
        let notificationDelivery: any NotificationDelivering
        if isPackagedApplication {
            UNUserNotificationCenter.current().delegate = NotificationResponseDelegate.shared
            notificationDelivery = MacOSNotificationDelivery()
        } else {
            notificationDelivery = UnavailableNotificationDelivery()
        }
        let proofMode = ProcessInfo.processInfo.environment["ZOID99_MANUAL_NOTIFICATION_PROOF"] == "1"
        let persistence: any ResearchPersistence = proofMode
            ? JSONResearchPersistence(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("zoid99-issue-007-proof.json")
            )
            : JSONResearchPersistence.production()
        _store = StateObject(
            wrappedValue: AppStore(
                persistence: persistence,
                notificationDelivery: notificationDelivery
            )
        )
    }

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
            .onOpenURL(perform: store.openNotificationDeepLink)
            .onReceive(NotificationCenter.default.publisher(for: .zoid99OpenOpportunity)) { event in
                guard let url = event.object as? URL else { return }
                store.openNotificationDeepLink(url)
            }
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

        MenuBarExtra("Zoid 99", systemImage: "bell") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notifications: \(store.notificationPermission.rawValue)")
                Text("\(store.notifications.filter { !$0.isRead }.count) unread")
                Text(store.quietHoursEnabled
                    ? "Quiet hours \(String(format: "%02d:00", store.quietStartHour))-\(String(format: "%02d:00", store.quietEndHour))"
                    : "Quiet hours off")
                Divider()
                Button("Open Notifications") {
                    store.selectedDestination = .notifications
                }
            }
            .padding(8)
        }
    }
}
