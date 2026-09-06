import Foundation

enum MailProvider: String, Codable, Hashable, Sendable {
    case gmail
}

struct MailAccount: Identifiable, Codable, Hashable, Sendable {
    struct ID: RawRepresentable, Codable, Hashable, Sendable {
        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    enum ConnectionState: String, Codable, Hashable, Sendable {
        case connected
        case authenticationRequired
    }

    let id: ID
    let provider: MailProvider
    let emailAddress: String
    let displayName: String?
    let connectionState: ConnectionState

    var displayLabel: String {
        guard let displayName, !displayName.isEmpty else { return emailAddress }
        return displayName
    }
}
