import Foundation

protocol CredentialDataStoring: Sendable {
    func data(for accountID: MailAccount.ID) async throws -> Data?
    func save(_ data: Data, for accountID: MailAccount.ID) async throws
    func removeData(for accountID: MailAccount.ID) async throws
}

enum SecureStorageError: Error, Equatable, Sendable {
    case unavailable
}
