import EventKit
import Foundation

@MainActor
final class EventKitReminderCreator: ReminderCreating {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func create(_ draft: ReminderDraft) async throws {
        try await requestAccessIfNeeded()

        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw ReminderCreationError.defaultListUnavailable
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = calendar
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.dueDateComponents = draft.dueDate.map { dueDate in
            Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
        }

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw ReminderCreationError.saveFailed
        }
    }

    private func requestAccessIfNeeded() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return
        case .notDetermined:
            do {
                guard try await eventStore.requestFullAccessToReminders() else {
                    throw ReminderCreationError.accessDenied
                }
            } catch let error as ReminderCreationError {
                throw error
            } catch {
                throw ReminderCreationError.unavailable
            }
        case .denied, .restricted, .writeOnly:
            throw ReminderCreationError.accessDenied
        @unknown default:
            throw ReminderCreationError.unavailable
        }
    }
}
