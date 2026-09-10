import Observation

@MainActor
@Observable
final class AccountsViewModel {
    private let gateway: any AccountGateway

    private(set) var accounts: [MailAccount] = []
    private(set) var isLoading = false
    private(set) var hasLoadedAccounts = false
    private(set) var errorMessage: String?

    init(gateway: any AccountGateway) {
        self.gateway = gateway
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            accounts = try await gateway.connectedAccounts()
            hasLoadedAccounts = true
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Connected accounts couldn’t be loaded."
        }
    }

    func connectGmail() async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await gateway.connect(provider: .gmail)
            accounts = try await gateway.connectedAccounts()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch let error as AccountManagementError where error == .configurationMissing {
            errorMessage = "Google OAuth isn’t configured for this build."
        } catch {
            errorMessage = "The Gmail account couldn’t be connected."
        }
    }

    func reconnect(_ account: MailAccount) async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await gateway.reconnect(account)
            accounts = try await gateway.connectedAccounts()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Authentication couldn’t be restored for \(account.emailAddress)."
        }
    }

    func disconnect(_ account: MailAccount) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await gateway.disconnect(account)
            accounts.removeAll { $0.id == account.id }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "The account couldn’t be removed."
        }
    }

    func dismissError() {
        errorMessage = nil
    }
}
