import Foundation

struct EmailAnalysisInput: Identifiable, Hashable, Sendable {
    let id: EmailMessage.ID
    let sender: String
    let subject: String
    let receivedAt: Date
    let text: String
}

enum EmailPriority: String, Codable, CaseIterable, Hashable, Sendable {
    case low
    case medium
    case high
    case critical

    var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .critical: 3
        }
    }
}

enum ImportanceReason: String, Codable, CaseIterable, Hashable, Sendable {
    case directMessage
    case jobOrRecruiting
    case securityAlert
    case billingOrPayment
    case accountProblem
    case deadline
    case responseRequest
    case appointmentOrSchedule
    case workCommunication
    case otherImportant
    case newsletter
    case promotion
    case automatedNotification
    case lowValue
}

struct EmailAssessment: Hashable, Sendable {
    let emailID: EmailMessage.ID
    let isImportant: Bool
    let priority: EmailPriority
    let summary: String
    let actionRequired: Bool
    let actionDescription: String?
    let reason: ImportanceReason

    var isValid: Bool {
        if isImportant && summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if actionRequired {
            return !(actionDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        return true
    }
}

struct AnalyzedEmail: Identifiable, Hashable, Sendable {
    var id: EmailMessage.ID { message.id }

    let message: EmailMessage
    let assessment: EmailAssessment
}
