import Foundation

@MainActor
struct AppContainer {
    let briefingViewModel: BriefingViewModel
    let accountsViewModel: AccountsViewModel

    static func live(configuration: AppConfiguration = .load()) -> AppContainer {
        let transport = URLSessionHTTPTransport()
        let credentials = KeychainCredentialStore(service: "com.tinpham.InboxBrief.gmail-oauth")
        let metadata = UserDefaultsAccountMetadataStore()
        let accounts = AppAuthGmailAuthenticationService(
            configuration: configuration.googleOAuth,
            credentials: credentials,
            metadata: metadata,
            transport: transport
        )

        guard let gmailBaseURL = URL(string: "https://gmail.googleapis.com/gmail/v1") else {
            return unconfigured()
        }
        let emailFetcher = GmailRecentEmailFetcher(
            transport: transport,
            tokens: accounts,
            baseURL: gmailBaseURL
        )
        let analyzer: any EmailAnalyzing = switch configuration.aiConnection {
        case let .openAI(endpoint, key, model):
            OpenAIEmailAnalyzer(
                transport: transport,
                endpoint: endpoint,
                apiKey: key,
                model: model
            )
        case let .gemini(endpoint, key, model):
            GeminiEmailAnalyzer(
                transport: transport,
                endpoint: endpoint,
                apiKey: key,
                model: model
            )
        case let .fitAI(endpoint, key, model, maximumConcurrentBatches):
            FITAIEmailAnalyzer(
                transport: transport,
                endpoint: endpoint,
                apiKey: key,
                model: model,
                maximumConcurrentBatches: maximumConcurrentBatches
            )
        case let .proxy(endpoint):
            ProxyEmailAnalyzer(transport: transport, endpoint: endpoint)
        case .unavailable:
            UnconfiguredEmailAnalyzer()
        }
        let useCase = GenerateInboxBriefUseCase(
            accounts: accounts,
            emailFetcher: emailFetcher,
            analyzer: analyzer
        )
        return AppContainer(
            briefingViewModel: BriefingViewModel(
                generateBrief: useCase,
                messageOpener: SystemOriginalMessageOpener()
            ),
            accountsViewModel: AccountsViewModel(gateway: accounts)
        )
    }

    private static func unconfigured() -> AppContainer {
        let accounts = UnconfiguredAccountGateway()
        let useCase = GenerateInboxBriefUseCase(
            accounts: accounts,
            emailFetcher: UnconfiguredEmailFetcher(),
            analyzer: UnconfiguredEmailAnalyzer()
        )
        return AppContainer(
            briefingViewModel: BriefingViewModel(
                generateBrief: useCase,
                messageOpener: UnconfiguredMessageOpener()
            ),
            accountsViewModel: AccountsViewModel(gateway: accounts)
        )
    }
}

@MainActor
private struct UnconfiguredAccountGateway: AccountGateway {
    func connectedAccounts() async throws -> [MailAccount] { [] }
    func connect(provider: MailProvider) async throws -> MailAccount {
        throw AccountManagementError.configurationMissing
    }
    func reconnect(_ account: MailAccount) async throws -> MailAccount {
        throw AccountManagementError.configurationMissing
    }
    func disconnect(_ account: MailAccount) async throws {}
}

private struct UnconfiguredEmailFetcher: RecentEmailFetching {
    func fetchRecentEmails(for account: MailAccount, since cutoff: Date) async throws -> [EmailMessage] {
        throw MailFetchError.providerUnavailable
    }
}

private struct UnconfiguredEmailAnalyzer: EmailAnalyzing {
    func analyze(
        _ messages: [EmailAnalysisInput],
        progress: @escaping @Sendable (OperationProgress) async -> Void
    ) async throws -> [EmailAssessment] {
        throw EmailAnalysisFailure.configurationMissing
    }
}

private struct UnconfiguredMessageOpener: OriginalMessageOpening {
    @MainActor
    func open(_ target: OriginalMessageTarget) async -> Bool { false }
}
