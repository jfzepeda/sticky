@preconcurrency import EventKit
import Foundation
import StickyCore

/// Thin, thread-agnostic wrapper over `EKEventStore`. Only `Sendable` values
/// (`ReminderList`, `ImportedReminder`) leave this type; `EKReminder`/`EKCalendar`
/// never cross an isolation boundary.
///
/// `@unchecked Sendable`: the only state is an `EKEventStore`, which Apple documents as
/// safe to use from any thread; every method is a self-contained call into it.
final class RemindersGateway: @unchecked Sendable {
    private let store = EKEventStore()

    static var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    /// macOS 14+: full read access to Reminders.
    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    func lists() -> [ReminderList] {
        store.calendars(for: .reminder)
            .map { calendar in
                ReminderList(
                    id: calendar.calendarIdentifier,
                    name: calendar.title,
                    color: calendar.cgColor.flatMap(RGBA.init(cgColor:)) ?? .vanilla
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Incomplete reminders from exactly the given lists. An empty selection returns `[]`
    /// (passing `nil` calendars to EventKit would mean *all* lists).
    func incompleteReminders(inListsWithIDs ids: Set<String>) async -> [ImportedReminder] {
        let calendars = store.calendars(for: .reminder).filter { ids.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: calendars
        )
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                // Map inside the callback: EKReminder is not Sendable.
                let mapped = (reminders ?? []).compactMap { reminder -> ImportedReminder? in
                    guard let calendar = reminder.calendar else { return nil }
                    return ImportedReminder(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        listID: calendar.calendarIdentifier,
                        listName: calendar.title,
                        listColor: calendar.cgColor.flatMap(RGBA.init(cgColor:)) ?? .vanilla
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    /// `EKEventStoreChanged` from any store in this process (the app only creates this one).
    /// Not filtered by `object:` because that parameter must be Sendable and EKEventStore isn't.
    var changes: NotificationCenter.Notifications {
        NotificationCenter.default.notifications(named: .EKEventStoreChanged)
    }
}
