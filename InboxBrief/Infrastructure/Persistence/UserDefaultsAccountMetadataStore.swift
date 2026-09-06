import Foundation

actor UserDefaultsAccountMetadataStore: AccountMetadataStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = "connectedMailAccounts") {
        self.defaults = defaults
        self.key = key
    }

    func accounts() throws -> [MailAccount] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try decoder.decode([MailAccount].self, from: data)
        } catch {
            throw AccountManagementError.storageUnavailable
        }
    }

    func save(_ account: MailAccount) throws {
        var values = try accounts()
        values.removeAll { $0.id == account.id }
        values.append(account)
        try persist(values)
    }

    func remove(_ accountID: MailAccount.ID) throws {
        var values = try accounts()
        values.removeAll { $0.id == accountID }
        try persist(values)
    }

    private func persist(_ accounts: [MailAccount]) throws {
        do {
            defaults.set(try encoder.encode(accounts), forKey: key)
        } catch {
            throw AccountManagementError.storageUnavailable
        }
    }
}
