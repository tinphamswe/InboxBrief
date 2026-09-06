import Foundation

struct AIAnalysisCodec: Sendable {
    struct InputEnvelope: Encodable, Sendable {
        struct Message: Encodable, Sendable {
            let messageID: String
            let sender: String
            let subject: String
            let receivedAt: String
            let excerpt: String
        }

        let messages: [Message]
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func encodeInput(_ messages: [EmailAnalysisInput]) throws -> Data {
        let envelope = InputEnvelope(
            messages: messages.map {
                InputEnvelope.Message(
                    messageID: $0.id.rawValue,
                    sender: $0.sender,
                    subject: $0.subject,
                    receivedAt: $0.receivedAt.ISO8601Format(),
                    excerpt: $0.text
                )
            }
        )
        return try encoder.encode(envelope)
    }

    func decodeAnalysis(_ data: Data) throws -> [EmailAssessment] {
        let response = try decoder.decode(AIAnalysisResponseDTO.self, from: data)
        return response.results.map {
            EmailAssessment(
                emailID: .init(rawValue: $0.messageID),
                isImportant: $0.isImportant,
                priority: $0.priority,
                summary: $0.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                actionRequired: $0.actionRequired,
                actionDescription: $0.actionDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
                reason: $0.reason
            )
        }
    }

    func decodeOpenAIResponse(_ data: Data) throws -> [EmailAssessment] {
        let response = try decoder.decode(OpenAIResponseDTO.self, from: data)
        guard response.status == nil || response.status == "completed" else {
            throw EmailAnalysisFailure.invalidResponse
        }
        if response.output
            .flatMap({ $0.content ?? [] })
            .contains(where: { $0.type == "refusal" }) {
            throw EmailAnalysisFailure.refused
        }
        guard let text = response.output
            .flatMap({ $0.content ?? [] })
            .first(where: { $0.type == "output_text" })?
            .text,
              let analysisData = text.data(using: .utf8)
        else {
            throw EmailAnalysisFailure.invalidResponse
        }
        return try decodeAnalysis(analysisData)
    }

    func decodeGeminiResponse(_ data: Data) throws -> [EmailAssessment] {
        let response = try decoder.decode(GeminiInteractionResponseDTO.self, from: data)
        guard response.status == nil || response.status == "completed",
              let output = response.steps.last(where: { $0.type == "model_output" })
        else {
            throw EmailAnalysisFailure.invalidResponse
        }
        let text = (output.content ?? [])
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty, let analysisData = text.data(using: .utf8) else {
            throw EmailAnalysisFailure.invalidResponse
        }
        return try decodeAnalysis(analysisData)
    }

    func decodeFITAIResponse(_ data: Data) throws -> [EmailAssessment] {
        let response = try decoder.decode(FITAIChatCompletionResponseDTO.self, from: data)
        guard let message = response.choices.first?.message else {
            throw EmailAnalysisFailure.invalidResponse
        }

        let toolArguments = message.toolCalls?
            .first(where: { $0.function.name == "submit_email_triage" })?
            .function.arguments
        guard let output = toolArguments ?? message.content,
              let analysisData = sanitizedJSONObject(output).data(using: .utf8)
        else {
            throw EmailAnalysisFailure.invalidResponse
        }
        return try decodeAnalysis(analysisData)
    }

    private func sanitizedJSONObject(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else {
            return trimmed
        }

        var lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return trimmed }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var outputSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "results": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "message_id": ["type": "string"],
                            "is_important": ["type": "boolean"],
                            "priority": ["type": "string", "enum": EmailPriority.allCases.map(\.rawValue)],
                            "summary": ["type": "string"],
                            "action_required": ["type": "boolean"],
                            "action_description": ["type": ["string", "null"]],
                            "reason": ["type": "string", "enum": ImportanceReason.allCases.map(\.rawValue)],
                        ],
                        "required": [
                            "message_id", "is_important", "priority", "summary",
                            "action_required", "action_description", "reason",
                        ],
                    ],
                ],
            ],
            "required": ["results"],
        ]
    }
}
