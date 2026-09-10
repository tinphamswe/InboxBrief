import Foundation
import Testing
@testable import InboxBrief

@Suite("Create reminder draft")
struct CreateReminderDraftUseCaseTests {
    @Test("creates an editable, minimal reminder for an actionable email")
    func createsDraft() {
        let message = makeMessage(originalURL: URL(string: "https://mail.google.com/mail/u/0/#all/message"))
        let email = AnalyzedEmail(message: message, assessment: assessment(actionRequired: true))

        let draft = CreateReminderDraftUseCase().execute(for: email)

        #expect(draft?.id == message.id)
        #expect(draft?.title == "Reply with the revised timeline.")
        #expect(draft?.dueDate == nil)
        #expect(draft?.notes.contains("Summary: The sender needs a revised delivery timeline.") == true)
        #expect(draft?.notes.contains("Open original: https://mail.google.com/mail/u/0/#all/message") == true)
        #expect(draft?.notes.contains(message.analysisText) == false)
    }

    @Test("does not create a reminder for an email without a required action")
    func ignoresNonActionableEmail() {
        let email = AnalyzedEmail(message: makeMessage(originalURL: nil), assessment: assessment(actionRequired: false))

        #expect(CreateReminderDraftUseCase().execute(for: email) == nil)
    }

    private func makeMessage(originalURL: URL?) -> EmailMessage {
        EmailMessage(
            id: .init(rawValue: "message"),
            accountID: .init(rawValue: "account"),
            accountAddress: "person@example.com",
            sender: EmailSender(name: "Taylor", address: "taylor@example.com"),
            subject: "Project timeline",
            receivedAt: Date(timeIntervalSince1970: 2_000_000_000),
            analysisText: "This raw body must not be added to the reminder.",
            originalTarget: originalURL.map { OriginalMessageTarget(webURL: $0, searchQuery: nil) }
        )
    }

    private func assessment(actionRequired: Bool) -> EmailAssessment {
        EmailAssessment(
            emailID: .init(rawValue: "message"),
            isImportant: true,
            priority: .high,
            summary: "The sender needs a revised delivery timeline.",
            actionRequired: actionRequired,
            actionDescription: actionRequired ? "Reply with the revised timeline." : nil,
            reason: .responseRequest
        )
    }
}
