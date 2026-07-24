import SwiftUI
import AppKit
import UserNotifications

enum AppWindowMetrics {
    static let minimumWidth: CGFloat = 980
    static let minimumHeight: CGFloat = 680
}

@MainActor
enum MainWindowFramePersistence {
    static let autosaveName = "Zoid99.MainWindow"
    static let frameDefaultsKey = "Zoid99.MainWindowFrame"

    @discardableResult
    static func configure(_ window: NSWindow) -> Bool {
        guard window.frameAutosaveName != autosaveName else { return true }
        window.setFrameAutosaveName("")
        return window.setFrameAutosaveName(autosaveName)
    }

    @discardableResult
    static func restore(_ window: NSWindow) -> Bool {
        if let values = UserDefaults.standard.array(forKey: frameDefaultsKey) as? [Double],
           values.count == 4 {
            let frame = NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
            let isUsable = frame.width > 0
                && frame.height > 0
                && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
                && NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
            if isUsable {
                window.setFrame(frame, display: false)
                return true
            }
        }
        return window.setFrameUsingName(autosaveName)
    }

    static func save(_ window: NSWindow) {
        window.saveFrame(usingName: autosaveName)
        UserDefaults.standard.set(
            [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height],
            forKey: frameDefaultsKey
        )
    }
}

@MainActor
private final class MainWindowFramePersistenceController: NSObject {
    static let shared = MainWindowFramePersistenceController()

    private var hasStarted = false
    private weak var observedWindow: NSWindow?
    private var lastSavedFrame: NSRect?
    private var timer: Timer?

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let frameTimer = Timer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(synchronizeFrame),
            userInfo: nil,
            repeats: true
        )
        timer = frameTimer
        RunLoop.main.add(frameTimer, forMode: .common)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        synchronizeFrame()
    }

    @objc private func synchronizeFrame() {
        guard let window = NSApplication.shared.windows.first(where: {
            $0.title == "Zoid 99" && $0.styleMask.contains(.titled)
        }) else {
            return
        }

        if observedWindow !== window {
            observedWindow = window
            MainWindowFramePersistence.restore(window)
            MainWindowFramePersistence.configure(window)
            lastSavedFrame = window.frame
            return
        }

        guard lastSavedFrame != window.frame else { return }
        MainWindowFramePersistence.save(window)
        lastSavedFrame = window.frame
    }
}

@main
struct Zoid99App: App {
    @StateObject private var store: AppStore

    init() {
        MainWindowFramePersistenceController.shared.start()
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
            .frame(
                minWidth: AppWindowMetrics.minimumWidth,
                minHeight: AppWindowMetrics.minimumHeight
            )
            .task {
                guard store.setupComplete else { return }
                store.startScheduledRefresh()
            }
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
                Button("Open Topics") { store.selectedDestination = .topics }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Open Comments") { store.selectedDestination = .comments }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Open Watchlists") { store.selectedDestination = .watchlists }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Open Notifications") { store.selectedDestination = .notifications }
                    .keyboardShortcut("6", modifiers: [.command])
                Button("Open Sources and Settings") { store.selectedDestination = .settings }
                    .keyboardShortcut("7", modifiers: [.command])
                Divider()
                Button("Focus Search") {
                    store.selectedDestination = .radar
                    Task { @MainActor in
                        await Task.yield()
                        store.requestSearchFocus()
                    }
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
        }

        MenuBarExtra("Zoid 99", systemImage: "bell") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notifications: \(store.notificationPermission.rawValue)")
                Text("\(store.notifications.filter { !$0.isRead }.count) unread")
                Text("Sources: \(store.connectedSourceCount)/6 connected")
                Text(store.lastRefreshAt.map {
                    "Last refresh: \($0.formatted(date: .abbreviated, time: .shortened))"
                } ?? "Last refresh: no successful sync")
                Text("Status: \(store.statusMessage)")
                Text(store.quietHoursEnabled
                    ? "Quiet hours \(String(format: "%02d:00", store.quietStartHour))-\(String(format: "%02d:00", store.quietEndHour))"
                    : "Quiet hours off")
                Divider()
                Button(store.isRefreshing ? "Refreshing research" : "Refresh research") {
                    Task { await store.refresh() }
                }
                .disabled(store.isRefreshing)
                Button("Open Notifications") {
                    store.selectedDestination = .notifications
                }
            }
            .padding(8)
        }
    }
}
