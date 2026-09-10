import Foundation

struct ReminderDraft: Identifiable, Hashable, Sendable {
    let id: EmailMessage.ID
    var title: String
    var notes: String
    var dueDate: Date?
}
