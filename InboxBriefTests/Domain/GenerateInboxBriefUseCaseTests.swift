import Foundation
import Testing
@testable import InboxBrief

@Suite("Generate inbox brief")
struct GenerateInboxBriefUseCaseTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("aggregates multiple accounts and records scan statistics")
    func aggregatesMultipleAccounts() async throws {
        let personal = Fixtures.account("personal")
        let work = Fixtures.account("work")
        let first = Fixtures.message("first", account: personal, receivedAt: now.addingTimeInterval(-60))
        let second = Fixtures.message("second", account: work, receivedAt: now.addingTimeInterval(-120))
        let sut = makeUseCase(
            accounts: [personal, work],
            results: [personal.id: .success([first]), work.id: .success([second])],
            assessments: [
                Fixtures.assessment(for: first, important: true, priority: .medium),
                Fixtures.assessment(for: second, important: true, priority: .high),
            ]
        )
        let progressRecorder = BriefProgressRecorder()

        let brief = try await sut.execute { progress in
            await progressRecorder.record(progress)
        }
        let progress = await progressRecorder.values()

        #expect(brief.statistics.accountsAttempted == 2)
        #expect(brief.statistics.accountsSucceeded == 2)
        #expect(brief.statistics.emailsScanned == 2)
        #expect(brief.statistics.importantEmails == 2)
        #expect(brief.emails.map(\.id) == [second.id, first.id])
        #expect(brief.scanCutoff == now.addingTimeInterval(-86_400))
        #expect(progress == [
            .fetching(OperationProgress(completed: 0, total: 2)),
            .fetching(OperationProgress(completed: 1, total: 2)),
            .fetching(OperationProgress(completed: 2, total: 2)),
            .analyzing(OperationProgress(completed: 0, total: 2)),
            .analyzing(OperationProgress(completed: 2, total: 2)),
        ])
    }

    @Test("reports no connected accounts without calling dependencies")
    func noConnectedAccounts() async {
        let sut = makeUseCase(accounts: [], results: [:], assessments: [])

        await #expect(throws: BriefGenerationError.noConnectedAccounts) {
            try await sut.execute()
        }
    }

    @Test("returns a successful empty brief when inboxes contain no mail")
    func noRecentEmails() async throws {
        let account = Fixtures.account("empty")
        let sut = makeUseCase(
            accounts: [account],
            results: [account.id: .success([])],
            assessments: []
        )

        let brief = try await sut.execute()

        #expect(brief.emails.isEmpty)
        #expect(brief.statistics.emailsScanned == 0)
        #expect(brief.statistics.importantEmails == 0)
        #expect(brief.statistics.accountsSucceeded == 1)
    }

    @Test("filters unimportant messages")
    func filtersUnimportantMessages() async throws {
        let account = Fixtures.account("filter")
        let important = Fixtures.message("security", account: account, receivedAt: now)
        let marketing = Fixtures.message("sale", account: account, receivedAt: now)
        let sut = makeUseCase(
            accounts: [account],
            results: [account.id: .success([important, marketing])],
            assessments: [
                Fixtures.assessment(for: important, important: true, priority: .critical),
                Fixtures.assessment(for: marketing, important: false, priority: .low),
            ]
        )

        let brief = try await sut.execute()

        #expect(brief.statistics.emailsScanned == 2)
        #expect(brief.emails.map(\.id) == [important.id])
    }

    @Test("sorts equal priorities by newest receipt date")
    func sortsByDateWithinPriority() async throws {
        let account = Fixtures.account("sort")
        let older = Fixtures.message("older", account: account, receivedAt: now.addingTimeInterval(-500))
        let newer = Fixtures.message("newer", account: account, receivedAt: now.addingTimeInterval(-10))
        let sut = makeUseCase(
            accounts: [account],
            results: [account.id: .success([older, newer])],
            assessments: [
                Fixtures.assessment(for: older, important: true, priority: .high),
                Fixtures.assessment(for: newer, important: true, priority: .high),
            ]
        )

        let brief = try await sut.execute()

        #expect(brief.emails.map(\.id) == [newer.id, older.id])
    }

    @Test("preserves successful accounts when another account fails")
    func partialAccountFailure() async throws {
        let working = Fixtures.account("working")
        let expired = Fixtures.account("expired")
        let message = Fixtures.message("message", account: working, receivedAt: now)
        let sut = makeUseCase(
            accounts: [working, expired],
            results: [
                working.id: .success([message]),
                expired.id: .failure(.authenticationExpired),
            ],
            assessments: [Fixtures.assessment(for: message, important: true, priority: .high)]
        )

        let brief = try await sut.execute()

        #expect(brief.statistics.isPartial)
        #expect(brief.statistics.accountsSucceeded == 1)
        #expect(brief.statistics.failures == [
            AccountScanFailure(account: expired, reason: .authenticationExpired),
        ])
        #expect(brief.emails.count == 1)
    }

    @Test("throws a typed failure when every account fails")
    func completeAccountFailure() async {
        let offline = Fixtures.account("offline")
        let unavailable = Fixtures.account("unavailable")
        let sut = makeUseCase(
            accounts: [offline, unavailable],
            results: [
                offline.id: .failure(.offline),
                unavailable.id: .failure(.providerUnavailable),
            ],
            assessments: []
        )
        let expected = BriefGenerationError.allAccountsFailed([
            AccountScanFailure(account: offline, reason: .offline),
            AccountScanFailure(account: unavailable, reason: .providerUnavailable),
        ])

        await #expect(throws: expected) {
            try await sut.execute()
        }
    }

    @Test("rejects incomplete AI results")
    func incompleteAnalysis() async {
        let account = Fixtures.account("analysis")
        let first = Fixtures.message("first", account: account, receivedAt: now)
        let second = Fixtures.message("second", account: account, receivedAt: now)
        let sut = makeUseCase(
            accounts: [account],
            results: [account.id: .success([first, second])],
            assessments: [Fixtures.assessment(for: first, important: true, priority: .high)]
        )

        await #expect(throws: BriefGenerationError.analysisUnavailable(.invalidResponse)) {
            try await sut.execute()
        }
    }

    @Test("rejects invalid action assessments")
    func invalidActionAssessment() async {
        let account = Fixtures.account("invalid")
        let message = Fixtures.message("message", account: account, receivedAt: now)
        let invalid = EmailAssessment(
            emailID: message.id,
            isImportant: true,
            priority: .high,
            summary: "Reply requested.",
            actionRequired: true,
            actionDescription: nil,
            reason: .responseRequest
        )
        let sut = makeUseCase(
            accounts: [account],
            results: [account.id: .success([message])],
            assessments: [invalid]
        )

        await #expect(throws: BriefGenerationError.analysisUnavailable(.invalidResponse)) {
            try await sut.execute()
        }
    }

    @Test("limits text sent for analysis to two thousand characters")
    func limitsAnalysisText() async throws {
        let account = Fixtures.account("privacy")
        let message = EmailMessage(
            id: .init(rawValue: "privacy:long"),
            accountID: account.id,
            accountAddress: account.emailAddress,
            sender: EmailSender(name: "Sender", address: "sender@example.com"),
            subject: "Long message",
            receivedAt: now,
            analysisText: String(repeating: "x", count: 3_000),
            originalTarget: nil
        )
        let analyzer = CapturingEmailAnalyzer(assessments: [
            Fixtures.assessment(for: message, important: false, priority: .low),
        ])
        let sut = GenerateInboxBriefUseCase(
            accounts: FakeAccountGateway(accounts: [account]),
            emailFetcher: FakeRecentEmailFetcher(results: [account.id: .success([message])]),
            analyzer: analyzer,
            dateProvider: DateProvider(now: { now })
        )

        _ = try await sut.execute()
        let inputs = await analyzer.recordedInputs()

        #expect(inputs.first?.text.count == 2_000)
    }

    private func makeUseCase(
        accounts: [MailAccount],
        results: [MailAccount.ID: Result<[EmailMessage], MailFetchError>],
        assessments: [EmailAssessment]
    ) -> GenerateInboxBriefUseCase {
        GenerateInboxBriefUseCase(
            accounts: FakeAccountGateway(accounts: accounts),
            emailFetcher: FakeRecentEmailFetcher(results: results),
            analyzer: FakeEmailAnalyzer(assessments: assessments),
            dateProvider: DateProvider(now: { now })
        )
    }
}

@MainActor
private struct FakeAccountGateway: AccountGateway {
    let accounts: [MailAccount]

    func connectedAccounts() async throws -> [MailAccount] { accounts }
    func connect(provider: MailProvider) async throws -> MailAccount { throw TestError.notImplemented }
    func reconnect(_ account: MailAccount) async throws -> MailAccount { throw TestError.notImplemented }
    func disconnect(_ account: MailAccount) async throws { throw TestError.notImplemented }
}

private struct FakeRecentEmailFetcher: RecentEmailFetching {
    let results: [MailAccount.ID: Result<[EmailMessage], MailFetchError>]

    func fetchRecentEmails(for account: MailAccount, since cutoff: Date) async throws -> [EmailMessage] {
        guard let result = results[account.id] else { throw TestError.missingFixture }
        return try result.get()
    }
}

private struct FakeEmailAnalyzer: EmailAnalyzing {
    let assessments: [EmailAssessment]

    func analyze(
        _ messages: [EmailAnalysisInput],
        progress: @escaping @Sendable (OperationProgress) async -> Void
    ) async throws -> [EmailAssessment] {
        await progress(OperationProgress(completed: messages.count, total: messages.count))
        return assessments
    }
}

private actor CapturingEmailAnalyzer: EmailAnalyzing {
    private let assessments: [EmailAssessment]
    private var inputs: [EmailAnalysisInput] = []

    init(assessments: [EmailAssessment]) {
        self.assessments = assessments
    }

    func analyze(
        _ messages: [EmailAnalysisInput],
        progress: @escaping @Sendable (OperationProgress) async -> Void
    ) async throws -> [EmailAssessment] {
        inputs = messages
        await progress(OperationProgress(completed: messages.count, total: messages.count))
        return assessments
    }

    func recordedInputs() -> [EmailAnalysisInput] {
        inputs
    }
}

private actor BriefProgressRecorder {
    private var progress: [InboxBriefGenerationProgress] = []

    func record(_ value: InboxBriefGenerationProgress) {
        progress.append(value)
    }

    func values() -> [InboxBriefGenerationProgress] {
        progress
    }
}

private enum TestError: Error {
    case missingFixture
    case notImplemented
}

private enum Fixtures {
    static func account(_ value: String) -> MailAccount {
        MailAccount(
            id: .init(rawValue: value),
            provider: .gmail,
            emailAddress: "\(value)@example.com",
            displayName: value.capitalized,
            connectionState: .connected
        )
    }

    static func message(_ value: String, account: MailAccount, receivedAt: Date) -> EmailMessage {
        EmailMessage(
            id: .init(rawValue: "\(account.id.rawValue):\(value)"),
            accountID: account.id,
            accountAddress: account.emailAddress,
            sender: EmailSender(name: "Sender", address: "sender@example.com"),
            subject: value.capitalized,
            receivedAt: receivedAt,
            analysisText: "Please review \(value).",
            originalTarget: nil
        )
    }

    static func assessment(
        for message: EmailMessage,
        important: Bool,
        priority: EmailPriority
    ) -> EmailAssessment {
        EmailAssessment(
            emailID: message.id,
            isImportant: important,
            priority: priority,
            summary: important ? "This needs attention." : "",
            actionRequired: important,
            actionDescription: important ? "Review it today." : nil,
            reason: important ? .responseRequest : .promotion
        )
    }
}
