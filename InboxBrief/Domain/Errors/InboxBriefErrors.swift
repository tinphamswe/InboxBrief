import Foundation

enum MailFetchError: Error, Equatable, Sendable {
    case authenticationExpired
    case offline
    case providerUnavailable
    case invalidResponse
}

enum EmailAnalysisFailure: Error, Equatable, Sendable {
    case configurationMissing
    case authenticationFailed
    case permissionDenied
    case rateLimited
    case offline
    case serviceUnavailable
    case invalidRequest
    case invalidResponse
    case refused
}

enum BriefGenerationError: Error, Equatable, Sendable {
    case noConnectedAccounts
    case accountsUnavailable
    case allAccountsFailed([AccountScanFailure])
    case analysisUnavailable(EmailAnalysisFailure)
}

enum AccountManagementError: Error, Equatable, Sendable {
    case configurationMissing
    case authenticationFailed
    case storageUnavailable
}

enum ReminderCreationError: Error, Equatable, Sendable {
    case accessDenied
    case unavailable
    case defaultListUnavailable
    case saveFailed
}
