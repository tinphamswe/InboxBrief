import Foundation

struct EmailSender: Hashable, Sendable {
    let name: String?
    let address: String

    var displayName: String {
        guard let name, !name.isEmpty else { return address }
        return name
    }
}

struct OriginalMessageTarget: Hashable, Sendable {
    let webURL: URL
    let searchQuery: String?
}

struct EmailMessage: Identifiable, Hashable, Sendable {
    struct ID: RawRepresentable, Hashable, Sendable {
        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    let id: ID
    let accountID: MailAccount.ID
    let accountAddress: String
    let sender: EmailSender
    let subject: String
    let receivedAt: Date
    let analysisText: String
    let originalTarget: OriginalMessageTarget?
}
