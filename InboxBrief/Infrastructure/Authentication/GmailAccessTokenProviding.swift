@MainActor
protocol GmailAccessTokenProviding: Sendable {
    func accessToken(for accountID: MailAccount.ID, forceRefresh: Bool) async throws -> String
}

enum AccessTokenError: Error, Equatable, Sendable {
    case authenticationRequired
    case unavailable
}
