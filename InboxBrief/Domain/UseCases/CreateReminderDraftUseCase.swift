import Foundation

struct CreateReminderDraftUseCase: Sendable {
    func execute(for email: AnalyzedEmail) -> ReminderDraft? {
        guard email.assessment.actionRequired,
              let action = email.assessment.actionDescription?.trimmed,
              !action.isEmpty else {
            return nil
        }

        var notes = [
            "From: \(email.message.sender.displayName)",
            "Subject: \(email.message.subject)",
            "Account: \(email.message.accountAddress)",
            "Received: \(email.message.receivedAt.formatted(date: .abbreviated, time: .shortened))",
            "",
            "Summary: \(email.assessment.summary)",
        ]

        if let originalURL = email.message.originalTarget?.webURL {
            notes += ["", "Open original: \(originalURL.absoluteString)"]
        }

        return ReminderDraft(
            id: email.id,
            title: action,
            notes: notes.joined(separator: "\n"),
            dueDate: nil
        )
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
