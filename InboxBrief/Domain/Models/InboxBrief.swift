import Foundation

struct AccountScanFailure: Identifiable, Hashable, Sendable {
    enum Reason: String, Error, Hashable, Sendable {
        case authenticationExpired
        case offline
        case providerUnavailable
        case invalidResponse
        case unknown
    }

    var id: MailAccount.ID { account.id }

    let account: MailAccount
    let reason: Reason
}

struct InboxBriefStatistics: Hashable, Sendable {
    let accountsAttempted: Int
    let accountsSucceeded: Int
    let emailsScanned: Int
    let importantEmails: Int
    let failures: [AccountScanFailure]

    var isPartial: Bool {
        accountsSucceeded > 0 && accountsSucceeded < accountsAttempted
    }
}

struct InboxBrief: Hashable, Sendable {
    let scanStartedAt: Date
    let scanCutoff: Date
    let generatedAt: Date
    let statistics: InboxBriefStatistics
    let emails: [AnalyzedEmail]
}
