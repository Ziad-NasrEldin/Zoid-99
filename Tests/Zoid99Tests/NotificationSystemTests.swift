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

    func testQuietHoursDefersImmediateAlertUntilQuietHoursEnd() async {
        let delivery = RecordingNotificationDelivery(permission: .authorized)
        let coordinator = NotificationCoordinator(delivery: delivery)
        let now = date(2027, 1, 15, 23)
        var settings = AppSettings.defaults
        settings.notificationsEnabled = true
        settings.notificationPermission = .authorized
        settings.quietHoursEnabled = true
        settings.quietStartHour = 22
        settings.quietEndHour = 8

        _ = await coordinator.process(
            candidates: [record("Urgent research", delivery: .immediate, suffix: 3, now: now)],
            existing: [],
            settings: settings,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(delivery.requests[0].scheduledAt, date(2027, 1, 16, 8))
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
