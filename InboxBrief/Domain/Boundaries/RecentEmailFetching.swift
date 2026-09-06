import Foundation

protocol RecentEmailFetching: Sendable {
    func fetchRecentEmails(for account: MailAccount, since cutoff: Date) async throws -> [EmailMessage]
}
