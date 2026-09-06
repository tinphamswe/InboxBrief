@MainActor
protocol AccountGateway: Sendable {
    func connectedAccounts() async throws -> [MailAccount]
    func connect(provider: MailProvider) async throws -> MailAccount
    func reconnect(_ account: MailAccount) async throws -> MailAccount
    func disconnect(_ account: MailAccount) async throws
}
