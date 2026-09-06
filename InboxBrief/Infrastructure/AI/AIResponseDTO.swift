import Foundation

struct AIAnalysisResponseDTO: Decodable, Sendable {
    let results: [AIAnalysisResultDTO]
}

struct AIAnalysisResultDTO: Decodable, Sendable {
    let messageID: String
    let isImportant: Bool
    let priority: EmailPriority
    let summary: String
    let actionRequired: Bool
    let actionDescription: String?
    let reason: ImportanceReason

    private enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case isImportant = "is_important"
        case priority
        case summary
        case actionRequired = "action_required"
        case actionDescription = "action_description"
        case reason
    }
}

struct OpenAIResponseDTO: Decodable, Sendable {
    struct Output: Decodable, Sendable {
        struct Content: Decodable, Sendable {
            let type: String
            let text: String?
        }

        let type: String
        let content: [Content]?
    }

    let status: String?
    let output: [Output]
}

struct GeminiInteractionResponseDTO: Decodable, Sendable {
    struct Step: Decodable, Sendable {
        struct Content: Decodable, Sendable {
            let type: String
            let text: String?
        }

        let type: String
        let content: [Content]?
    }

    let status: String?
    let steps: [Step]
}

struct FITAIChatCompletionResponseDTO: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Message: Decodable, Sendable {
            struct ToolCall: Decodable, Sendable {
                struct Function: Decodable, Sendable {
                    let name: String
                    let arguments: String
                }

                let function: Function
            }

            let content: String?
            let toolCalls: [ToolCall]?

            private enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }

        let message: Message
    }

    let choices: [Choice]
}
