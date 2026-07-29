import XCTest
@testable import Zoid99

final class NotificationSystemTests: XCTestCase {
    func testHighPriorityAlertSchedulesImmediatelyAndCarriesOpportunityDeepLink() async {
        let delivery = RecordingNotificationDelivery(permission: .authorized)
        let coordinator = NotificationCoordinator(delivery: delivery)
        let opportunityID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = NotificationRecord(
            id: UUID(),
            opportunityID: opportunityID,
            title: "Confirmed model release",
            delivery: .immediate,
            createdAt: now,
            isRead: false
        )
        var settings = AppSettings.defaults
        settings.notificationsEnabled = true
        settings.notificationPermission = .authorized

        let result = await coordinator.process(
            candidates: [candidate],
            existing: [],
            settings: settings,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(result.records.map(\.deliveryState), [.scheduled])
        XCTAssertEqual(delivery.requests.count, 1)
        XCTAssertEqual(delivery.requests[0].scheduledAt, now)
        XCTAssertEqual(delivery.requests[0].deepLink.absoluteString, "zoid99://opportunity/\(opportunityID.uuidString)")
    }

    func testLowerPriorityItemsAreCombinedIntoOneDigest() async {
        let delivery = RecordingNotificationDelivery(permission: .authorized)
        let coordinator = NotificationCoordinator(delivery: delivery)
        let now = date(2027, 1, 15, 12)
        var settings = AppSettings.defaults
        settings.notificationsEnabled = true
        settings.notificationPermission = .authorized
        settings.digestHour = 18
        let candidates = [
            record("First research update", delivery: .digest, suffix: 1, now: now),
            record("Second research update", delivery: .digest, suffix: 2, now: now)
        ]

        let result = await coordinator.process(
            candidates: candidates,
            existing: [],
            settings: settings,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(delivery.requests.count, 1)
        XCTAssertEqual(delivery.requests[0].title, "Zoid 99 - Research digest")
        XCTAssertEqual(delivery.requests[0].body, "2 lower-priority opportunities are ready to review.")
        XCTAssertEqual(delivery.requests[0].scheduledAt, date(2027, 1, 15, 18))
        XCTAssertEqual(result.records.map(\.deliveryState), [.scheduled, .scheduled])
    }

    func testLegacyQuietHoursCannotDeferImmediateAlertOvernight() async {
        let delivery = RecordingNotificationDelivery(permission: .authorized)
        let coordinator = NotificationCoordinator(delivery: delivery)
        let now = date(2027, 1, 15, 23)
        var settings = AppSettings.defaults
        settings.notificationsEnabled = true
        settings.notificationPermission = .authorized

        let result = await coordinator.process(
            candidates: [record("Urgent research", delivery: .immediate, suffix: 3, now: now)],
            existing: [],
            settings: settings,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(delivery.requests[0].scheduledAt, now)
        XCTAssertEqual(result.records[0].scheduledAt, now)
        XCTAssertEqual(result.records[0].statusDetail, "Scheduled with macOS.")
    }

    func testLegacyQuietHoursSettingsDecodeWithoutPersistingSuppressionPolicy() throws {
        let legacy = """
        {
          "setupComplete": true,
          "refreshMinutes": 15,
          "notificationPermissionRequested": true,
          "notificationsEnabled": true,
          "notificationPermission": "Allowed",
          "quietHoursEnabled": true,
          "quietStartHour": 22,
          "quietEndHour": 8,
          "digestHour": 18,
          "discordEnabled": true,
          "discordHighPriorityEnabled": true,
          "discordDeliveredOpportunityIDs": []
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        let encoded = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertTrue(settings.notificationsEnabled)
        XCTAssertTrue(settings.discordEnabled)
        XCTAssertNil(object["quietHoursEnabled"])
        XCTAssertNil(object["quietStartHour"])
        XCTAssertNil(object["quietEndHour"])
    }

    func testLegacyDeferredRecordIsMadeEligibleForImmediateRescheduling() {
        let now = date(2027, 1, 15, 23)
        var legacy = record("Urgent research", delivery: .immediate, suffix: 9, now: now)
        legacy.deliveryState = .scheduled
        legacy.scheduledAt = date(2027, 1, 16, 8)
        legacy.statusDetail = "Deferred until quiet hours end."

        let migrated = NotificationCoordinator.migratingLegacyQuietHours([legacy])

        XCTAssertEqual(migrated[0].deliveryState, .awaitingPermission)
        XCTAssertNil(migrated[0].scheduledAt)
        XCTAssertEqual(migrated[0].statusDetail, "Eligible for immediate 24/7 delivery.")
    }

    func testDeniedPermissionCreatesTruthfulDurableFailureWithoutScheduling() async {
        let delivery = RecordingNotificationDelivery(permission: .denied)
        let coordinator = NotificationCoordinator(delivery: delivery)
        let now = date(2027, 1, 15, 12)
        var settings = AppSettings.defaults
        settings.notificationsEnabled = true
        settings.notificationPermission = .denied

        let result = await coordinator.process(
            candidates: [record("Urgent research", delivery: .immediate, suffix: 4, now: now)],
            existing: [],
            settings: settings,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertTrue(delivery.requests.isEmpty)
        XCTAssertEqual(result.records[0].deliveryState, .failed)
        XCTAssertEqual(result.records[0].statusDetail, "Blocked by macOS notification permission. Open System Settings to allow Zoid 99.")
    }

    func testRestartedCoordinatorDoesNotScheduleSameOpportunityTwice() async {
        let delivery = RecordingNotificationDelivery(permission: .authorized)
        let coordinator = NotificationCoordinator(delivery: delivery)
        let now = date(2027, 1, 15, 12)
        var settings = AppSettings.defaults
        settings.notificationsEnabled = true
        settings.notificationPermission = .authorized
        let candidate = record("Urgent research", delivery: .immediate, suffix: 5, now: now)

        let first = await coordinator.process(
            candidates: [candidate],
            existing: [],
            settings: settings,
            now: now,
            calendar: utcCalendar
        )
        let second = await coordinator.process(
            candidates: [candidate],
            existing: first.records,
            settings: settings,
            now: now.addingTimeInterval(60),
            calendar: utcCalendar
        )

        XCTAssertEqual(delivery.requests.count, 1)
        XCTAssertEqual(second.records.count, 1)
    }

    func testPreviouslyScheduledDigestIsNotReplayedWhenTheAlertPolicyChanges() async {
        let delivery = RecordingNotificationDelivery(permission: .authorized)
        let coordinator = NotificationCoordinator(delivery: delivery)
        let now = date(2027, 1, 15, 12)
        var settings = AppSettings.defaults
        settings.notificationsEnabled = true
        settings.notificationPermission = .authorized
        let opportunityID = UUID(uuidString: "00000000-0000-0000-0000-000000000550")!
        var scheduledDigest = NotificationRecord(
            id: UUID(),
            opportunityID: opportunityID,
            title: "Previously queued research",
            delivery: .digest,
            createdAt: now,
            isRead: false
        )
        scheduledDigest.deliveryState = .scheduled
        scheduledDigest.scheduledAt = date(2027, 1, 15, 18)
        let newImmediateCandidate = NotificationRecord(
            id: UUID(),
            opportunityID: opportunityID,
            title: "Previously queued research",
            delivery: .immediate,
            createdAt: now,
            isRead: false
        )

        let result = await coordinator.process(
            candidates: [newImmediateCandidate],
            existing: [scheduledDigest],
            settings: settings,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertTrue(delivery.requests.isEmpty)
        XCTAssertEqual(result.records, [scheduledDigest])
    }

    func testAlertWaitingForPermissionSchedulesAfterUserOptsIn() async {
        let delivery = RecordingNotificationDelivery(permission: .notDetermined)
        let coordinator = NotificationCoordinator(delivery: delivery)
        let now = date(2027, 1, 15, 12)
        var settings = AppSettings.defaults
        settings.notificationsEnabled = true
        let candidate = record("Urgent research", delivery: .immediate, suffix: 6, now: now)

        let waiting = await coordinator.process(
            candidates: [candidate],
            existing: [],
            settings: settings,
            now: now,
            calendar: utcCalendar
        )
        delivery.permission = .authorized
        settings.notificationPermission = .authorized
        let scheduled = await coordinator.process(
            candidates: [candidate],
            existing: waiting.records,
            settings: settings,
            now: now.addingTimeInterval(60),
            calendar: utcCalendar
        )

        XCTAssertEqual(scheduled.records.count, 1)
        XCTAssertEqual(scheduled.records[0].deliveryState, .scheduled)
        XCTAssertEqual(delivery.requests.count, 1)
    }

    func testLaterRefreshUpdatesSameDigestWithFullDurableCount() async {
        let delivery = RecordingNotificationDelivery(permission: .authorized)
        let coordinator = NotificationCoordinator(delivery: delivery)
        let now = date(2027, 1, 15, 12)
        var settings = AppSettings.defaults
        settings.notificationsEnabled = true
        settings.notificationPermission = .authorized
        settings.digestHour = 18

        let first = await coordinator.process(
            candidates: [record("First", delivery: .digest, suffix: 7, now: now)],
            existing: [],
            settings: settings,
            now: now,
            calendar: utcCalendar
        )
        _ = await coordinator.process(
            candidates: [
                record("First", delivery: .digest, suffix: 7, now: now),
                record("Second", delivery: .digest, suffix: 8, now: now)
            ],
            existing: first.records,
            settings: settings,
            now: now.addingTimeInterval(60),
            calendar: utcCalendar
        )

        XCTAssertEqual(delivery.requests.count, 2)
        XCTAssertEqual(delivery.requests[0].identifier, delivery.requests[1].identifier)
        XCTAssertEqual(delivery.requests[1].body, "2 lower-priority opportunities are ready to review.")
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func record(
        _ title: String,
        delivery: NotificationRecord.Delivery,
        suffix: Int,
        now: Date
    ) -> NotificationRecord {
        NotificationRecord(
            id: UUID(),
            opportunityID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!,
            title: title,
            delivery: delivery,
            createdAt: now,
            isRead: false
        )
    }
}

private final class RecordingNotificationDelivery: NotificationDelivering, @unchecked Sendable {
    var permission: NotificationPermissionState
    var requests: [NativeNotificationRequest] = []

    init(permission: NotificationPermissionState) {
        self.permission = permission
    }

    func permissionState() async -> NotificationPermissionState { permission }

    func requestPermission() async throws -> NotificationPermissionState { permission }

    func schedule(_ request: NativeNotificationRequest) async throws {
        requests.append(request)
    }
}
