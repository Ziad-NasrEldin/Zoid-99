import Foundation
@preconcurrency import UserNotifications

struct NativeNotificationRequest: Sendable, Equatable {
    let identifier: String
    let title: String
    let body: String
    let scheduledAt: Date
    let deepLink: URL
}

protocol NotificationDelivering: Sendable {
    func permissionState() async -> NotificationPermissionState
    func requestPermission() async throws -> NotificationPermissionState
    func schedule(_ request: NativeNotificationRequest) async throws
}

struct UnavailableNotificationDelivery: NotificationDelivering {
    func permissionState() async -> NotificationPermissionState { .unavailable }
    func requestPermission() async throws -> NotificationPermissionState { .unavailable }
    func schedule(_ request: NativeNotificationRequest) async throws {
        throw NotificationDeliveryError.unavailable
    }
}

enum NotificationDeliveryError: Error {
    case unavailable
}

struct NotificationProcessingResult: Sendable {
    let records: [NotificationRecord]
    let permission: NotificationPermissionState
}

struct NotificationCoordinator: Sendable {
    let delivery: any NotificationDelivering

    func process(
        candidates: [NotificationRecord],
        existing: [NotificationRecord],
        settings: AppSettings,
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> NotificationProcessingResult {
        let terminalOpportunityIDs = Set(existing.filter {
            $0.deliveryState == .scheduled || $0.deliveryState == .delivered
        }.map(\.opportunityID))
        let candidateOpportunityIDs = Set(candidates.map(\.opportunityID))
        let retained = existing.filter {
            terminalOpportunityIDs.contains($0.opportunityID)
                || !candidateOpportunityIDs.contains($0.opportunityID)
        }
        let fresh = candidates.filter { !terminalOpportunityIDs.contains($0.opportunityID) }
        guard !fresh.isEmpty else {
            return NotificationProcessingResult(records: existing, permission: settings.notificationPermission)
        }

        guard settings.notificationsEnabled else {
            return NotificationProcessingResult(
                records: retained + fresh.map {
                    updating(
                        $0,
                        state: .suppressed,
                        detail: "Notifications are off in Zoid 99 settings."
                    )
                },
                permission: settings.notificationPermission
            )
        }

        let permission = await delivery.permissionState()
        guard permission == .authorized || permission == .provisional else {
            let state: NotificationRecord.DeliveryState = permission == .notDetermined
                ? .awaitingPermission
                : .failed
            let detail = permission == .denied
                ? "Blocked by macOS notification permission. Open System Settings to allow Zoid 99."
                : permission == .notDetermined
                    ? "Waiting for explicit notification permission."
                    : "Native notifications are unavailable on this Mac."
            return NotificationProcessingResult(
                records: retained + fresh.map { updating($0, state: state, detail: detail) },
                permission: permission
            )
        }

        var processed: [NotificationRecord] = []
        for candidate in fresh.filter({ $0.delivery == .immediate }) {
            let request = NativeNotificationRequest(
                identifier: candidate.id.uuidString,
                title: "Zoid 99 - High-priority opportunity",
                body: candidate.title,
                scheduledAt: now,
                deepLink: deepLink(for: candidate.opportunityID)
            )
            processed.append(await schedule(candidate, request: request))
        }

        let digest = fresh.filter { $0.delivery == .digest }
        if let first = digest.first {
            let scheduledAt = nextDigestDate(from: now, hour: settings.digestHour, calendar: calendar)
            let alreadyScheduled = existing.filter {
                $0.delivery == .digest
                    && $0.deliveryState == .scheduled
                    && $0.scheduledAt == scheduledAt
            }
            let completeDigest = alreadyScheduled + digest
            let deepLinkOpportunityID = completeDigest.first?.opportunityID ?? first.opportunityID
            let request = NativeNotificationRequest(
                identifier: "digest-\(Int(scheduledAt.timeIntervalSince1970))",
                title: "Zoid 99 - Research digest",
                body: "\(completeDigest.count) lower-priority opportunit\(completeDigest.count == 1 ? "y is" : "ies are") ready to review.",
                scheduledAt: scheduledAt,
                deepLink: deepLink(for: deepLinkOpportunityID)
            )
            do {
                try await delivery.schedule(request)
                processed += digest.map {
                    updating(
                        $0,
                        state: .scheduled,
                        scheduledAt: scheduledAt,
                        detail: "Included in the next research digest."
                    )
                }
            } catch {
                processed += digest.map {
                    updating(
                        $0,
                        state: .failed,
                        detail: "macOS could not schedule the research digest."
                    )
                }
            }
        }

        return NotificationProcessingResult(records: retained + processed, permission: permission)
    }

    private func schedule(
        _ record: NotificationRecord,
        request: NativeNotificationRequest
    ) async -> NotificationRecord {
        do {
            try await delivery.schedule(request)
            return updating(
                record,
                state: .scheduled,
                scheduledAt: request.scheduledAt,
                detail: "Scheduled with macOS."
            )
        } catch {
            return updating(
                record,
                state: .failed,
                detail: "macOS could not schedule this notification."
            )
        }
    }

    private func updating(
        _ record: NotificationRecord,
        state: NotificationRecord.DeliveryState,
        scheduledAt: Date? = nil,
        detail: String
    ) -> NotificationRecord {
        var result = record
        result.deliveryState = state
        result.scheduledAt = scheduledAt
        result.statusDetail = detail
        return result
    }

    private func deepLink(for opportunityID: UUID) -> URL {
        URL(string: "zoid99://opportunity/\(opportunityID.uuidString)")!
    }

    static func migratingLegacyQuietHours(_ records: [NotificationRecord]) -> [NotificationRecord] {
        records.map { record in
            guard record.delivery == .immediate,
                  record.deliveryState == .scheduled,
                  record.statusDetail == "Deferred until quiet hours end."
            else { return record }
            var migrated = record
            migrated.deliveryState = .awaitingPermission
            migrated.scheduledAt = nil
            migrated.statusDetail = "Eligible for immediate 24/7 delivery."
            return migrated
        }
    }

    private func nextDigestDate(from now: Date, hour: Int, calendar: Calendar) -> Date {
        let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)!
    }
}

final class MacOSNotificationDelivery: NotificationDelivering, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    func permissionState() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: return .authorized
        case .provisional, .ephemeral: return .provisional
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }

    func requestPermission() async throws -> NotificationPermissionState {
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await permissionState()
    }

    func schedule(_ request: NativeNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = [
            "deepLink": request.deepLink.absoluteString,
            "opportunityID": request.deepLink.lastPathComponent
        ]
        let interval = max(1, request.scheduledAt.timeIntervalSinceNow)
        let trigger = interval <= 1 ? nil : UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try await center.add(
            UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
        )
    }
}

final class NotificationResponseDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationResponseDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let value = response.notification.request.content.userInfo["deepLink"] as? String,
              let url = URL(string: value)
        else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .zoid99OpenOpportunity, object: url)
        }
    }
}

extension Notification.Name {
    static let zoid99OpenOpportunity = Notification.Name("Zoid99OpenOpportunity")
}
