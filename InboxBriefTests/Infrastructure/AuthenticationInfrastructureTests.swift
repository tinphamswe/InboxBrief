import Foundation
import Testing
@testable import InboxBrief

@MainActor
@Suite("Authentication infrastructure")
struct AuthenticationInfrastructureTests {
    @Test("marks an account for reauthentication when credentials are missing")
    func missingCredentials() async throws {
        let account = makeAccount()
        let credentials = MemoryCredentialStore()
        let metadata = MemoryAccountStore(accounts: [account])
        let service = AppAuthGmailAuthenticationService(
            configuration: nil,
            credentials: credentials,
            metadata: metadata,
            transport: AuthenticationTransport()
        )

        let accounts = try await service.connectedAccounts()

        #expect(accounts.first?.connectionState == .authenticationRequired)
        #expect(await metadata.accounts().first?.connectionState == .authenticationRequired)
    }

    @Test("missing credentials produce a typed access-token failure")
    func missingToken() async {
        let service = AppAuthGmailAuthenticationService(
            configuration: nil,
            credentials: MemoryCredentialStore(),
            metadata: MemoryAccountStore(accounts: []),
            transport: AuthenticationTransport()
        )

        await #expect(throws: AccessTokenError.authenticationRequired) {
            try await service.accessToken(for: .init(rawValue: "missing"), forceRefresh: false)
        }
    }

    @Test("disconnect removes local account metadata and credentials")
    func disconnect() async throws {
        let account = makeAccount()
        let credentials = MemoryCredentialStore(values: [account.id: Data("not-an-auth-state".utf8)])
        let metadata = MemoryAccountStore(accounts: [account])
        let service = AppAuthGmailAuthenticationService(
            configuration: nil,
            credentials: credentials,
            metadata: metadata,
            transport: AuthenticationTransport()
        )

        try await service.disconnect(account)

        #expect(await credentials.data(for: account.id) == nil)
        #expect(await metadata.accounts().isEmpty)
    }

    private func makeAccount() -> MailAccount {
        MailAccount(
            id: .init(rawValue: "gmail:subject"),
            provider: .gmail,
            emailAddress: "person@example.com",
            displayName: "Person",
            connectionState: .connected
        )
    }
}

private actor MemoryCredentialStore: CredentialDataStoring {
    private var values: [MailAccount.ID: Data]

    init(values: [MailAccount.ID: Data] = [:]) {
        self.values = values
    }

    func data(for accountID: MailAccount.ID) -> Data? { values[accountID] }
    func save(_ data: Data, for accountID: MailAccount.ID) { values[accountID] = data }
    func removeData(for accountID: MailAccount.ID) { values.removeValue(forKey: accountID) }
}

private actor MemoryAccountStore: AccountMetadataStoring {
    private var values: [MailAccount]

    init(accounts: [MailAccount]) {
        values = accounts
    }

    func accounts() -> [MailAccount] { values }

    func save(_ account: MailAccount) {
        values.removeAll { $0.id == account.id }
        values.append(account)
    }

    func remove(_ accountID: MailAccount.ID) {
        values.removeAll { $0.id == accountID }
    }
}

private struct AuthenticationTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        HTTPResponse(data: Data(), statusCode: 503, headers: [:])
    }
}
