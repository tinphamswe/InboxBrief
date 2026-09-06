import Foundation
import Testing
@testable import InboxBrief

@MainActor
@Suite("Briefing view model")
struct BriefingViewModelTests {
    @Test("starts idle")
    func initialState() {
        let viewModel = makeViewModel(accounts: [])
        #expect(viewModel.state == .idle)
    }

    @Test("shows a successful result")
    func success() async {
        let account = account("success")
        let message = message("important", account: account)
        let viewModel = makeViewModel(accounts: [account], messages: [message])

        await viewModel.refresh()

        guard case let .loaded(brief) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(brief.emails.count == 1)
    }

    @Test("shows an empty result")
    func empty() async {
        let account = account("empty")
        let viewModel = makeViewModel(accounts: [account], messages: [])

        await viewModel.refresh()

        guard case let .empty(brief) = viewModel.state else {
            Issue.record("Expected empty state")
            return
        }
        #expect(brief.statistics.accountsSucceeded == 1)
    }

    @Test("maps no accounts to onboarding")
    func noAccounts() async {
        let viewModel = makeViewModel(accounts: [])
        await viewModel.refresh()
        #expect(viewModel.state == .needsAccounts)
    }

    @Test("retains partial account results")
    func partial() async {
        let good = account("good")
        let expired = account("expired")
        let viewModel = makeViewModel(
            accounts: [good, expired],
            fetchResults: [
                good.id: .success([message("important", account: good)]),
                expired.id: .failure(.authenticationExpired),
            ]
        )

        await viewModel.refresh()

        guard case let .loaded(brief) = viewModel.state else {
            Issue.record("Expected partial loaded state")
            return
        }
        #expect(brief.statistics.isPartial)
    }

    @Test("maps complete inbox failure")
    func error() async {
        let account = account("offline")
        let viewModel = makeViewModel(
            accounts: [account],
            fetchResults: [account.id: .failure(.offline)]
        )

        await viewModel.refresh()

        #expect(viewModel.state == .failed(.inboxesUnavailable, previous: nil))
    }

    @Test("preserves the safe AI failure category")
    func analysisError() async {
        let account = account("analysis-error")
        let message = message("message", account: account)
        let useCase = GenerateInboxBriefUseCase(
            accounts: ViewModelAccountGateway(accounts: [account]),
            emailFetcher: ViewModelFetcher(results: [account.id: .success([message])]),
            analyzer: ThrowingViewModelAnalyzer(failure: .authenticationFailed),
            dateProvider: DateProvider(now: { Date(timeIntervalSince1970: 100_000) })
        )
        let viewModel = BriefingViewModel(generateBrief: useCase, messageOpener: ViewModelOpener())

        await viewModel.refresh()

        #expect(viewModel.state == .failed(.analysisUnavailable(.authenticationFailed), previous: nil))
    }

    @Test("exposes loading while analysis is suspended")
    func loading() async {
        let account = account("loading")
        let message = message("message", account: account)
        let analyzer = GatedAnalyzer()
        let useCase = GenerateInboxBriefUseCase(
            accounts: ViewModelAccountGateway(accounts: [account]),
            emailFetcher: ViewModelFetcher(results: [account.id: .success([message])]),
            analyzer: analyzer,
            dateProvider: DateProvider(now: { Date(timeIntervalSince1970: 100_000) })
        )
        let viewModel = BriefingViewModel(generateBrief: useCase, messageOpener: ViewModelOpener())

        let refresh = Task { await viewModel.refresh() }
        await analyzer.waitUntilStarted()

        guard case let .loading(_, progress) = viewModel.state else {
            Issue.record("Expected loading state")
            return
        }
        #expect(progress == .analyzing(OperationProgress(completed: 0, total: 1)))
        await analyzer.complete(with: [assessment(for: message)])
        await refresh.value
        guard case .loaded = viewModel.state else {
            Issue.record("Expected loaded state after completing analysis")
            return
        }
    }

    @Test("button-owned refresh continues while loading UI replaces the button")
    func startedRefreshIsOwnedByViewModel() async {
        let account = account("owned-task")
        let message = message("message", account: account)
        let analyzer = GatedAnalyzer()
        let useCase = GenerateInboxBriefUseCase(
            accounts: ViewModelAccountGateway(accounts: [account]),
            emailFetcher: ViewModelFetcher(results: [account.id: .success([message])]),
            analyzer: analyzer,
            dateProvider: DateProvider(now: { Date(timeIntervalSince1970: 100_000) })
        )
        let viewModel = BriefingViewModel(generateBrief: useCase, messageOpener: ViewModelOpener())

        let refresh = viewModel.startRefresh()
        await analyzer.waitUntilStarted()

        #expect(viewModel.state.isLoading)
        await analyzer.complete(with: [assessment(for: message)])
        await refresh.value

        guard case .loaded = viewModel.state else {
            Issue.record("Expected the owned refresh to finish")
            return
        }
    }

    @Test("refresh replaces the previous briefing")
    func refresh() async {
        let account = account("refresh")
        let first = message("first", account: account)
        let second = message("second", account: account)
        let fetcher = SequencedFetcher(sequences: [[first], [second]])
        let useCase = GenerateInboxBriefUseCase(
            accounts: ViewModelAccountGateway(accounts: [account]),
            emailFetcher: fetcher,
            analyzer: EchoAnalyzer(),
            dateProvider: DateProvider(now: { Date(timeIntervalSince1970: 100_000) })
        )
        let viewModel = BriefingViewModel(generateBrief: useCase, messageOpener: ViewModelOpener())

        await viewModel.refresh()
        await viewModel.refresh()

        guard case let .loaded(brief) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(brief.emails.first?.id == second.id)
    }

    private func makeViewModel(
        accounts: [MailAccount],
        messages: [EmailMessage] = [],
        fetchResults: [MailAccount.ID: Result<[EmailMessage], MailFetchError>]? = nil
    ) -> BriefingViewModel {
        let results = fetchResults ?? Dictionary(
            uniqueKeysWithValues: accounts.map { account in
                (account.id, .success(messages.filter { $0.accountID == account.id }))
            }
        )
        let useCase = GenerateInboxBriefUseCase(
            accounts: ViewModelAccountGateway(accounts: accounts),
            emailFetcher: ViewModelFetcher(results: results),
            analyzer: EchoAnalyzer(),
            dateProvider: DateProvider(now: { Date(timeIntervalSince1970: 100_000) })
        )
        return BriefingViewModel(generateBrief: useCase, messageOpener: ViewModelOpener())
    }

    private func account(_ value: String) -> MailAccount {
        MailAccount(
            id: .init(rawValue: value),
            provider: .gmail,
            emailAddress: "\(value)@example.com",
            displayName: nil,
            connectionState: .connected
        )
    }

    private func message(_ value: String, account: MailAccount) -> EmailMessage {
        EmailMessage(
            id: .init(rawValue: value),
            accountID: account.id,
            accountAddress: account.emailAddress,
            sender: EmailSender(name: "Person", address: "person@example.com"),
            subject: value,
            receivedAt: Date(timeIntervalSince1970: 99_000),
            analysisText: "Please respond.",
            originalTarget: nil
        )
    }

    private func assessment(for message: EmailMessage) -> EmailAssessment {
        EmailAssessment(
            emailID: message.id,
            isImportant: true,
            priority: .high,
            summary: "A response is requested.",
            actionRequired: true,
            actionDescription: "Reply today.",
            reason: .responseRequest
        )
    }
}

@MainActor
private struct ViewModelAccountGateway: AccountGateway {
    let accounts: [MailAccount]

    func connectedAccounts() async throws -> [MailAccount] { accounts }
    func connect(provider: MailProvider) async throws -> MailAccount { throw AccountManagementError.authenticationFailed }
    func reconnect(_ account: MailAccount) async throws -> MailAccount { throw AccountManagementError.authenticationFailed }
    func disconnect(_ account: MailAccount) async throws {}
}

private struct ViewModelFetcher: RecentEmailFetching {
    let results: [MailAccount.ID: Result<[EmailMessage], MailFetchError>]

    func fetchRecentEmails(for account: MailAccount, since cutoff: Date) async throws -> [EmailMessage] {
        guard let result = results[account.id] else { return [] }
        return try result.get()
    }
}

private actor SequencedFetcher: RecentEmailFetching {
    private var sequences: [[EmailMessage]]

    init(sequences: [[EmailMessage]]) {
        self.sequences = sequences
    }

    func fetchRecentEmails(for account: MailAccount, since cutoff: Date) throws -> [EmailMessage] {
        guard !sequences.isEmpty else { return [] }
        return sequences.removeFirst()
    }
}

private struct EchoAnalyzer: EmailAnalyzing {
    func analyze(
        _ messages: [EmailAnalysisInput],
        progress: @escaping @Sendable (OperationProgress) async -> Void
    ) async throws -> [EmailAssessment] {
        let assessments = messages.map {
            EmailAssessment(
                emailID: $0.id,
                isImportant: true,
                priority: .high,
                summary: "A response is requested.",
                actionRequired: true,
                actionDescription: "Reply today.",
                reason: .responseRequest
            )
        }
        await progress(OperationProgress(completed: messages.count, total: messages.count))
        return assessments
    }
}

private struct ThrowingViewModelAnalyzer: EmailAnalyzing {
    let failure: EmailAnalysisFailure

    func analyze(
        _ messages: [EmailAnalysisInput],
        progress: @escaping @Sendable (OperationProgress) async -> Void
    ) async throws -> [EmailAssessment] {
        throw failure
    }
}

private actor GatedAnalyzer: EmailAnalyzing {
    private var resultContinuation: CheckedContinuation<[EmailAssessment], Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var started = false

    func analyze(
        _ messages: [EmailAnalysisInput],
        progress: @escaping @Sendable (OperationProgress) async -> Void
    ) async throws -> [EmailAssessment] {
        started = true
        startContinuation?.resume()
        startContinuation = nil
        let result = await withCheckedContinuation { resultContinuation = $0 }
        await progress(OperationProgress(completed: messages.count, total: messages.count))
        return result
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func complete(with result: [EmailAssessment]) {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}

private struct ViewModelOpener: OriginalMessageOpening {
    @MainActor
    func open(_ target: OriginalMessageTarget) async -> Bool { true }
}
