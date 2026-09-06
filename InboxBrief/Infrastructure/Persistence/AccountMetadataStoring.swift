protocol AccountMetadataStoring: Sendable {
    func accounts() async throws -> [MailAccount]
    func save(_ account: MailAccount) async throws
    func remove(_ accountID: MailAccount.ID) async throws
}
