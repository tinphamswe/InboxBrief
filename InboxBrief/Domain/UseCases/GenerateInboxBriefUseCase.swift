import Foundation

struct GenerateInboxBriefUseCase: Sendable {
    private struct AccountOutcome: Sendable {
        let index: Int
        let account: MailAccount
        let result: Result<[EmailMessage], AccountScanFailure.Reason>
    }

    private let accounts: any AccountGateway
    private let emailFetcher: any RecentEmailFetching
    private let analyzer: any EmailAnalyzing
    private let dateProvider: DateProvider
    private let scanInterval: TimeInterval
    private let maximumAnalysisCharacters: Int

    init(
        accounts: any AccountGateway,
        emailFetcher: any RecentEmailFetching,
        analyzer: any EmailAnalyzing,
        dateProvider: DateProvider = .live,
        scanInterval: TimeInterval = 24 * 60 * 60,
        maximumAnalysisCharacters: Int = 2_000
    ) {
        self.accounts = accounts
        self.emailFetcher = emailFetcher
        self.analyzer = analyzer
        self.dateProvider = dateProvider
        self.scanInterval = scanInterval
        self.maximumAnalysisCharacters = maximumAnalysisCharacters
    }

    func execute() async throws -> InboxBrief {
        try await execute(onProgress: { _ in })
    }

    func execute(
        onProgress: @escaping @Sendable (InboxBriefGenerationProgress) async -> Void
    ) async throws -> InboxBrief {
        let connectedAccounts: [MailAccount]
        do {
            connectedAccounts = try await accounts.connectedAccounts()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw BriefGenerationError.accountsUnavailable
        }

        guard !connectedAccounts.isEmpty else {
            throw BriefGenerationError.noConnectedAccounts
        }

        await onProgress(.fetching(OperationProgress(
            completed: 0,
            total: connectedAccounts.count
        )))
        let scanStartedAt = dateProvider.now()
        let cutoff = scanStartedAt.addingTimeInterval(-scanInterval)
        let outcomes = try await fetchAllAccounts(
            connectedAccounts,
            since: cutoff,
            onProgress: onProgress
        )
            .sorted { $0.index < $1.index }

        let failures = outcomes.compactMap { outcome -> AccountScanFailure? in
            guard case let .failure(reason) = outcome.result else { return nil }
            return AccountScanFailure(account: outcome.account, reason: reason)
        }
        let successfulMessages = outcomes.compactMap { outcome -> [EmailMessage]? in
            guard case let .success(messages) = outcome.result else { return nil }
            return messages
        }

        guard !successfulMessages.isEmpty else {
            throw BriefGenerationError.allAccountsFailed(failures)
        }

        let messages = successfulMessages.flatMap { $0 }
        await onProgress(.analyzing(OperationProgress(completed: 0, total: messages.count)))
        let analyzedEmails = try await analyze(messages) { progress in
            await onProgress(.analyzing(progress))
        }
            .filter { $0.assessment.isImportant }
            .sorted(by: Self.isOrderedBefore)

        return InboxBrief(
            scanStartedAt: scanStartedAt,
            scanCutoff: cutoff,
            generatedAt: dateProvider.now(),
            statistics: InboxBriefStatistics(
                accountsAttempted: connectedAccounts.count,
                accountsSucceeded: successfulMessages.count,
                emailsScanned: messages.count,
                importantEmails: analyzedEmails.count,
                failures: failures
            ),
            emails: analyzedEmails
        )
    }

    private func fetchAllAccounts(
        _ connectedAccounts: [MailAccount],
        since cutoff: Date,
        onProgress: @escaping @Sendable (InboxBriefGenerationProgress) async -> Void
    ) async throws -> [AccountOutcome] {
        try await withThrowingTaskGroup(of: AccountOutcome.self) { group in
            for (index, account) in connectedAccounts.enumerated() {
                group.addTask {
                    do {
                        let messages = try await emailFetcher.fetchRecentEmails(
                            for: account,
                            since: cutoff
                        )
                        return AccountOutcome(index: index, account: account, result: .success(messages))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        let reason = Self.failureReason(for: error)
                        return AccountOutcome(index: index, account: account, result: .failure(reason))
                    }
                }
            }

            var outcomes: [AccountOutcome] = []
            for try await outcome in group {
                outcomes.append(outcome)
                await onProgress(.fetching(OperationProgress(
                    completed: outcomes.count,
                    total: connectedAccounts.count
                )))
            }
            return outcomes
        }
    }

    private func analyze(
        _ messages: [EmailMessage],
        progress: @escaping @Sendable (OperationProgress) async -> Void
    ) async throws -> [AnalyzedEmail] {
        guard !messages.isEmpty else { return [] }

        let inputs = messages.map {
            EmailAnalysisInput(
                id: $0.id,
                sender: Self.analysisSender($0.sender),
                subject: $0.subject,
                receivedAt: $0.receivedAt,
                text: String($0.analysisText.prefix(maximumAnalysisCharacters))
            )
        }

        let assessments: [EmailAssessment]
        do {
            assessments = try await analyzer.analyze(inputs, progress: progress)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as EmailAnalysisFailure {
            throw BriefGenerationError.analysisUnavailable(failure)
        } catch {
            throw BriefGenerationError.analysisUnavailable(.serviceUnavailable)
        }

        var assessmentsByID: [EmailMessage.ID: EmailAssessment] = [:]
        for assessment in assessments {
            guard assessment.isValid, assessmentsByID[assessment.emailID] == nil else {
                throw BriefGenerationError.analysisUnavailable(.invalidResponse)
            }
            assessmentsByID[assessment.emailID] = assessment
        }

        guard assessmentsByID.count == messages.count else {
            throw BriefGenerationError.analysisUnavailable(.invalidResponse)
        }

        return try messages.map { message in
            guard let assessment = assessmentsByID[message.id] else {
                throw BriefGenerationError.analysisUnavailable(.invalidResponse)
            }
            return AnalyzedEmail(message: message, assessment: assessment)
        }
    }

    private static func failureReason(for error: any Error) -> AccountScanFailure.Reason {
        guard let fetchError = error as? MailFetchError else { return .unknown }
        return switch fetchError {
        case .authenticationExpired: .authenticationExpired
        case .offline: .offline
        case .providerUnavailable: .providerUnavailable
        case .invalidResponse: .invalidResponse
        }
    }

    private static func analysisSender(_ sender: EmailSender) -> String {
        guard sender.name != nil else { return sender.address }
        return "\(sender.displayName) <\(sender.address)>"
    }

    private static func isOrderedBefore(_ lhs: AnalyzedEmail, _ rhs: AnalyzedEmail) -> Bool {
        if lhs.assessment.priority.rank != rhs.assessment.priority.rank {
            return lhs.assessment.priority.rank > rhs.assessment.priority.rank
        }
        if lhs.message.receivedAt != rhs.message.receivedAt {
            return lhs.message.receivedAt > rhs.message.receivedAt
        }
        return lhs.message.subject.localizedStandardCompare(rhs.message.subject) == .orderedAscending
    }
}
