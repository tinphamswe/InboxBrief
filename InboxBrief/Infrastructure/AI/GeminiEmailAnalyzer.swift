import Foundation

struct GeminiEmailAnalyzer: EmailAnalyzing {
    private let transport: any HTTPTransport
    private let endpoint: URL
    private let apiKey: String
    private let model: String
    private let batchSize: Int
    private let codec: AIAnalysisCodec

    init(
        transport: any HTTPTransport,
        endpoint: URL,
        apiKey: String,
        model: String,
        batchSize: Int = 20,
        codec: AIAnalysisCodec = AIAnalysisCodec()
    ) {
        self.transport = transport
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.batchSize = max(1, batchSize)
        self.codec = codec
    }

    func analyze(
        _ messages: [EmailAnalysisInput],
        progress: @escaping @Sendable (OperationProgress) async -> Void
    ) async throws -> [EmailAssessment] {
        var assessments: [EmailAssessment] = []
        for start in stride(from: 0, to: messages.count, by: batchSize) {
            try Task.checkCancellation()
            let end = min(start + batchSize, messages.count)
            assessments.append(contentsOf: try await analyzeBatch(Array(messages[start..<end])))
            await progress(OperationProgress(completed: end, total: messages.count))
        }
        return assessments
    }

    private func analyzeBatch(_ messages: [EmailAnalysisInput]) async throws -> [EmailAssessment] {
        let inputData: Data
        do {
            inputData = try codec.encodeInput(messages)
        } catch {
            throw EmailAnalysisFailure.invalidRequest
        }
        guard let input = String(data: inputData, encoding: .utf8) else {
            throw EmailAnalysisFailure.invalidRequest
        }

        let body: [String: Any] = [
            "model": model,
            "store": false,
            "input": "\(EmailTriagePrompt.system)\n\nUntrusted email data follows as JSON:\n\(input)",
            "response_format": [
                "type": "text",
                "mime_type": "application/json",
                "schema": AIAnalysisCodec.outputSchema,
            ],
        ]
        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw EmailAnalysisFailure.invalidRequest
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let response = try await send(request)
        try validate(response.statusCode)
        do {
            return try codec.decodeGeminiResponse(response.data)
        } catch let failure as EmailAnalysisFailure {
            throw failure
        } catch {
            throw EmailAnalysisFailure.invalidResponse
        }
    }

    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw EmailAnalysisFailure.offline
        } catch {
            throw EmailAnalysisFailure.serviceUnavailable
        }
    }

    private func validate(_ statusCode: Int) throws {
        switch statusCode {
        case 200..<300:
            return
        case 401:
            throw EmailAnalysisFailure.authenticationFailed
        case 403:
            throw EmailAnalysisFailure.permissionDenied
        case 429:
            throw EmailAnalysisFailure.rateLimited
        case 400, 404, 422:
            throw EmailAnalysisFailure.invalidRequest
        default:
            throw EmailAnalysisFailure.serviceUnavailable
        }
    }
}
