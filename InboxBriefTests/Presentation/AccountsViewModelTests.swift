import Testing
@testable import InboxBrief

@MainActor
@Suite("Accounts view model")
struct AccountsViewModelTests {
    @Test("loads connected accounts")
    func load() async {
        let account = makeAccount("existing")
        let gateway = AccountsGatewayFake(accounts: [account])
        let viewModel = AccountsViewModel(gateway: gateway)

        await viewModel.load()

        #expect(viewModel.accounts == [account])
        #expect(viewModel.hasLoadedAccounts)
        #expect(!viewModel.isLoading)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("does not mark a failed account load as complete")
    func failedLoad() async {
        let gateway = AccountsGatewayFake(
            accounts: [],
            accountsError: .authenticationFailed
        )
        let viewModel = AccountsViewModel(gateway: gateway)

        await viewModel.load()

        #expect(!viewModel.hasLoadedAccounts)
        #expect(viewModel.errorMessage == "Connected accounts couldn’t be loaded.")
    }

    @Test("adds a Gmail account")
    func add() async {
        let account = makeAccount("new")
        let gateway = AccountsGatewayFake(accounts: [], accountToConnect: account)
        let viewModel = AccountsViewModel(gateway: gateway)

        await viewModel.connectGmail()

        #expect(viewModel.accounts == [account])
    }

    @Test("removes an account")
    func remove() async {
        let account = makeAccount("remove")
        let gateway = AccountsGatewayFake(accounts: [account])
        let viewModel = AccountsViewModel(gateway: gateway)
        await viewModel.load()

        await viewModel.disconnect(account)

        #expect(viewModel.accounts.isEmpty)
        #expect(gateway.disconnectedIDs == [account.id])
    }

    @Test("shows missing OAuth configuration")
    func missingConfiguration() async {
        let gateway = AccountsGatewayFake(accounts: [], connectError: .configurationMissing)
        let viewModel = AccountsViewModel(gateway: gateway)

        await viewModel.connectGmail()

        #expect(viewModel.errorMessage == "Google OAuth isn’t configured for this build.")
    }

    private func makeAccount(_ value: String) -> MailAccount {
        MailAccount(
            id: .init(rawValue: value),
            provider: .gmail,
            emailAddress: "\(value)@example.com",
            displayName: nil,
            connectionState: .connected
        )
    }
}

@MainActor
private final class AccountsGatewayFake: AccountGateway {
    private var storedAccounts: [MailAccount]
    private let accountToConnect: MailAccount?
    private let connectError: AccountManagementError?
    private let accountsError: AccountManagementError?
    private(set) var disconnectedIDs: [MailAccount.ID] = []

    init(
        accounts: [MailAccount],
        accountToConnect: MailAccount? = nil,
        connectError: AccountManagementError? = nil,
        accountsError: AccountManagementError? = nil
    ) {
        storedAccounts = accounts
        self.accountToConnect = accountToConnect
        self.connectError = connectError
        self.accountsError = accountsError
    }

    func connectedAccounts() async throws -> [MailAccount] {
        if let accountsError { throw accountsError }
        return storedAccounts
    }

    func connect(provider: MailProvider) async throws -> MailAccount {
        if let connectError { throw connectError }
        guard let accountToConnect else { throw AccountManagementError.authenticationFailed }
        storedAccounts.append(accountToConnect)
        return accountToConnect
    }

    func reconnect(_ account: MailAccount) async throws -> MailAccount { account }

    func disconnect(_ account: MailAccount) async throws {
        disconnectedIDs.append(account.id)
        storedAccounts.removeAll { $0.id == account.id }
    }
}
