import Foundation
import Testing
@testable import InboxBrief

@Suite("AI infrastructure")
struct AIInfrastructureTests {
    @Test("decodes a strongly typed analysis response")
    func decoding() throws {
        let data = Data(#"{"results":[{"message_id":"one","is_important":true,"priority":"high","summary":"Reply requested.","action_required":true,"action_description":"Reply today.","reason":"responseRequest"}]}"#.utf8)

        let results = try AIAnalysisCodec().decodeAnalysis(data)

        #expect(results == [EmailAssessment(
            emailID: .init(rawValue: "one"),
            isImportant: true,
            priority: .high,
            summary: "Reply requested.",
            actionRequired: true,
            actionDescription: "Reply today.",
            reason: .responseRequest
        )])
    }

    @Test("decodes a Gemini interaction into the shared analysis contract")
    func geminiDecoding() throws {
        let data = Data(#"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"{\"results\":[{\"message_id\":\"one\",\"is_important\":true,\"priority\":\"high\",\"summary\":\"Reply requested.\",\"action_required\":true,\"action_description\":\"Reply today.\",\"reason\":\"responseRequest\"}]}"}]}]}"#.utf8)

        let results = try AIAnalysisCodec().decodeGeminiResponse(data)

        #expect(results.first?.emailID == .init(rawValue: "one"))
        #expect(results.first?.priority == .high)
        #expect(results.first?.actionRequired == true)
    }

    @Test("decodes FIT-AI function arguments into the shared analysis contract")
    func fitAIDecoding() throws {
        let data = Data(#"{"choices":[{"message":{"content":null,"tool_calls":[{"type":"function","function":{"name":"submit_email_triage","arguments":"{\"results\":[{\"message_id\":\"one\",\"is_important\":true,\"priority\":\"high\",\"summary\":\"Reply requested.\",\"action_required\":true,\"action_description\":\"Reply today.\",\"reason\":\"responseRequest\"}]}"}}]}}]}"#.utf8)

        let results = try AIAnalysisCodec().decodeFITAIResponse(data)

        #expect(results.first?.emailID == .init(rawValue: "one"))
        #expect(results.first?.summary == "Reply requested.")
        #expect(results.first?.actionRequired == true)
    }

    @Test("rejects unknown enum values")
    func malformedStructuredOutput() {
        let data = Data(#"{"results":[{"message_id":"one","is_important":true,"priority":"urgent","summary":"Reply.","action_required":false,"action_description":null,"reason":"responseRequest"}]}"#.utf8)
        #expect(throws: (any Error).self) {
            try AIAnalysisCodec().decodeAnalysis(data)
        }
    }

    @Test("recognizes a provider refusal")
    func refusal() {
        let data = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal"}]}]}"#.utf8)
        #expect(throws: EmailAnalysisFailure.refused) {
            try AIAnalysisCodec().decodeOpenAIResponse(data)
        }
    }

    @Test("maps a provider HTTP error without exposing its payload")
    func providerError() async throws {
        let endpoint = try #require(URL(string: "https://example.test/responses"))
        let analyzer = OpenAIEmailAnalyzer(
            transport: FixedAITransport(response: HTTPResponse(
                data: Data("sensitive provider details".utf8),
                statusCode: 500,
                headers: [:]
            )),
            endpoint: endpoint,
            apiKey: "test-only",
            model: "test-model"
        )

        await #expect(throws: EmailAnalysisFailure.serviceUnavailable) {
            try await analyzer.analyze([EmailAnalysisInput(
                id: .init(rawValue: "one"),
                sender: "Sender",
                subject: "Subject",
                receivedAt: Date(timeIntervalSince1970: 1_000),
                text: "Excerpt"
            )])
        }
    }

    @Test("preserves safe provider HTTP failure categories")
    func providerHTTPFailureCategories() async throws {
        let cases: [(Int, EmailAnalysisFailure)] = [
            (400, .invalidRequest),
            (401, .authenticationFailed),
            (403, .permissionDenied),
            (429, .rateLimited),
            (503, .serviceUnavailable),
        ]

        for (statusCode, expectedFailure) in cases {
            let endpoint = try #require(URL(string: "https://example.test/responses"))
            let analyzer = OpenAIEmailAnalyzer(
                transport: FixedAITransport(response: HTTPResponse(
                    data: Data("sensitive provider details".utf8),
                    statusCode: statusCode,
                    headers: [:]
                )),
                endpoint: endpoint,
                apiKey: "test-only",
                model: "test-model"
            )

            await #expect(throws: expectedFailure) {
                try await analyzer.analyze([EmailAnalysisInput(
                    id: .init(rawValue: "one"),
                    sender: "Sender",
                    subject: "Subject",
                    receivedAt: Date(timeIntervalSince1970: 1_000),
                    text: "Excerpt"
                )])
            }
        }
    }

    @Test("Gemini sends minimized input and requests structured output")
    func geminiRequest() async throws {
        let responseData = Data(#"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"{\"results\":[{\"message_id\":\"one\",\"is_important\":false,\"priority\":\"low\",\"summary\":\"Newsletter.\",\"action_required\":false,\"action_description\":null,\"reason\":\"newsletter\"}]}"}]}]}"#.utf8)
        let transport = CapturingAITransport(response: HTTPResponse(
            data: responseData,
            statusCode: 200,
            headers: [:]
        ))
        let endpoint = try #require(URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions"))
        let analyzer = GeminiEmailAnalyzer(
            transport: transport,
            endpoint: endpoint,
            apiKey: "gemini-test-key",
            model: "gemini-test-model"
        )

        let results = try await analyzer.analyze([EmailAnalysisInput(
            id: .init(rawValue: "one"),
            sender: "Sender <sender@example.com>",
            subject: "Weekly news",
            receivedAt: Date(timeIntervalSince1970: 1_000),
            text: "Short normalized excerpt"
        )])
        let request = try #require(await transport.lastRequest())
        let bodyData = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let responseFormat = try #require(body["response_format"] as? [String: Any])

        #expect(results.first?.isImportant == false)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-test-key")
        #expect(body["model"] as? String == "gemini-test-model")
        #expect(body["store"] as? Bool == false)
        #expect(responseFormat["mime_type"] as? String == "application/json")
        #expect((body["input"] as? String)?.contains("Short normalized excerpt") == true)
    }

    @Test("Gemini preserves quota failures")
    func geminiQuotaFailure() async throws {
        let endpoint = try #require(URL(string: "https://example.test/interactions"))
        let analyzer = GeminiEmailAnalyzer(
            transport: FixedAITransport(response: HTTPResponse(
                data: Data("sensitive provider details".utf8),
                statusCode: 429,
                headers: [:]
            )),
            endpoint: endpoint,
            apiKey: "gemini-test-key",
            model: "gemini-test-model"
        )

        await #expect(throws: EmailAnalysisFailure.rateLimited) {
            try await analyzer.analyze([EmailAnalysisInput(
                id: .init(rawValue: "one"),
                sender: "Sender",
                subject: "Subject",
                receivedAt: Date(timeIntervalSince1970: 1_000),
                text: "Excerpt"
            )])
        }
    }

    @Test("FIT-AI uses Chat Completions with a forced typed function call")
    func fitAIRequest() async throws {
        let responseData = Data(#"{"choices":[{"message":{"content":null,"tool_calls":[{"type":"function","function":{"name":"submit_email_triage","arguments":"{\"results\":[{\"message_id\":\"one\",\"is_important\":false,\"priority\":\"low\",\"summary\":\"Newsletter.\",\"action_required\":false,\"action_description\":null,\"reason\":\"newsletter\"}]}"}}]}}]}"#.utf8)
        let transport = CapturingAITransport(response: HTTPResponse(
            data: responseData,
            statusCode: 200,
            headers: [:]
        ))
        let endpoint = try #require(URL(string: "https://api-fit.hcmus.edu.vn/v1/chat/completions"))
        let analyzer = FITAIEmailAnalyzer(
            transport: transport,
            endpoint: endpoint,
            apiKey: "fitai-test-key",
            model: "Qwen-27B",
            retryDelays: []
        )

        let results = try await analyzer.analyze([EmailAnalysisInput(
            id: .init(rawValue: "one"),
            sender: "Sender <sender@example.com>",
            subject: "Weekly news",
            receivedAt: Date(timeIntervalSince1970: 1_000),
            text: "Short normalized excerpt"
        )])
        let request = try #require(await transport.lastRequest())
        let bodyData = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let tools = try #require(body["tools"] as? [[String: Any]])
        let tool = try #require(tools.first?["function"] as? [String: Any])

        #expect(results.first?.isImportant == false)
        #expect(request.url == endpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fitai-test-key")
        #expect(body["model"] as? String == "Qwen-27B")
        #expect(body["stream"] as? Bool == false)
        #expect(body["max_tokens"] as? Int == 2_000)
        #expect((messages.first?["content"] as? String)?.contains("Routine security confirmations") == true)
        #expect((messages.first?["content"] as? String)?.contains("return an empty summary") == true)
        #expect(tool["name"] as? String == "submit_email_triage")
        #expect(tool["parameters"] != nil)
    }

    @Test("FIT-AI groups messages into eight-email batches")
    func fitAIBatching() async throws {
        let transport = BatchCountingAITransport()
        let endpoint = try #require(URL(string: "https://example.test/chat/completions"))
        let analyzer = FITAIEmailAnalyzer(
            transport: transport,
            endpoint: endpoint,
            apiKey: "fitai-test-key",
            model: "Qwen-27B",
            retryDelays: []
        )
        let inputs = (0..<31).map { index in
            EmailAnalysisInput(
                id: .init(rawValue: "message-\(index)"),
                sender: "Sender",
                subject: "Subject \(index)",
                receivedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                text: "Excerpt"
            )
        }

        let results = try await analyzer.analyze(inputs)
        let batchSizes = await transport.recordedBatchSizes().sorted()

        #expect(results.isEmpty)
        #expect(batchSizes == [7, 8, 8, 8])
    }

    @Test("FIT-AI applies bounded exponential backoff to quota responses")
    func fitAIBackoff() async throws {
        let successData = Data(#"{"choices":[{"message":{"content":"{\"results\":[{\"message_id\":\"one\",\"is_important\":false,\"priority\":\"low\",\"summary\":\"Not important.\",\"action_required\":false,\"action_description\":null,\"reason\":\"promotion\"}]}","tool_calls":null}}]}"#.utf8)
        let transport = SequencedAITransport(responses: [
            HTTPResponse(data: Data(), statusCode: 429, headers: [:]),
            HTTPResponse(data: Data(), statusCode: 429, headers: [:]),
            HTTPResponse(data: successData, statusCode: 200, headers: [:]),
        ])
        let sleeper = RecordingRetrySleeper()
        let endpoint = try #require(URL(string: "https://example.test/chat/completions"))
        let analyzer = FITAIEmailAnalyzer(
            transport: transport,
            endpoint: endpoint,
            apiKey: "fitai-test-key",
            model: "Qwen-27B",
            retryDelays: [.milliseconds(500), .seconds(1)],
            retrySleeper: sleeper
        )

        _ = try await analyzer.analyze([EmailAnalysisInput(
            id: .init(rawValue: "one"),
            sender: "Sender",
            subject: "Subject",
            receivedAt: Date(timeIntervalSince1970: 1_000),
            text: "Excerpt"
        )])

        let requestCount = await transport.requestCount()
        let delays = await sleeper.recordedDurations()
        #expect(requestCount == 3)
        #expect(delays == [.milliseconds(500), .seconds(1)])
    }

    @Test("Debug configuration prefers FIT-AI when its key is present")
    func fitAIConfiguration() {
        let configuration = AppConfiguration.load(environment: [
            "INBOXBRIEF_FITAI_API_KEY": "fitai-test-key",
            "INBOXBRIEF_GEMINI_API_KEY": "gemini-test-key",
        ])

        guard case let .fitAI(endpoint, key, model, maximumConcurrentBatches) = configuration.aiConnection else {
            Issue.record("Expected FIT-AI configuration")
            return
        }
        #expect(endpoint.absoluteString == "https://api-fit.hcmus.edu.vn/v1/chat/completions")
        #expect(key == "fitai-test-key")
        #expect(model == "Qwen-27B")
        #expect(maximumConcurrentBatches == 8)
    }

    @Test("FIT-AI concurrency can be reduced for a student key")
    func fitAIStudentConcurrencyConfiguration() {
        let configuration = AppConfiguration.load(environment: [
            "INBOXBRIEF_FITAI_API_KEY": "fitai-test-key",
            "INBOXBRIEF_FITAI_MAX_CONCURRENT_BATCHES": "3",
        ])

        guard case let .fitAI(_, _, _, maximumConcurrentBatches) = configuration.aiConnection else {
            Issue.record("Expected FIT-AI configuration")
            return
        }
        #expect(maximumConcurrentBatches == 3)
    }

    @Test("Debug configuration prefers Gemini when its key is present")
    func geminiConfiguration() {
        let configuration = AppConfiguration.load(environment: [
            "INBOXBRIEF_GEMINI_API_KEY": "gemini-test-key",
            "INBOXBRIEF_GEMINI_MODEL": "gemini-test-model",
            "INBOXBRIEF_OPENAI_API_KEY": "openai-test-key",
        ])

        guard case let .gemini(endpoint, key, model) = configuration.aiConnection else {
            Issue.record("Expected Gemini configuration")
            return
        }
        #expect(endpoint.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions")
        #expect(key == "gemini-test-key")
        #expect(model == "gemini-test-model")
    }
}

private struct FixedAITransport: HTTPTransport {
    let response: HTTPResponse
    func send(_ request: URLRequest) async throws -> HTTPResponse { response }
}

private actor CapturingAITransport: HTTPTransport {
    private let response: HTTPResponse
    private var request: URLRequest?

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        self.request = request
        return response
    }

    func lastRequest() -> URLRequest? {
        request
    }
}

private actor SequencedAITransport: HTTPTransport {
    private let responses: [HTTPResponse]
    private var index = 0

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let response = responses[min(index, responses.count - 1)]
        index += 1
        return response
    }

    func requestCount() -> Int {
        index
    }
}

private actor RecordingRetrySleeper: RetrySleeping {
    private var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
    }

    func recordedDurations() -> [Duration] {
        durations
    }
}

private actor BatchCountingAITransport: HTTPTransport {
    private var batchSizes: [Int] = []

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        guard let bodyData = request.httpBody,
              let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let chatMessages = body["messages"] as? [[String: Any]],
              let userContent = chatMessages.last?["content"] as? String,
              let jsonStart = userContent.firstIndex(of: "{"),
              let inputData = String(userContent[jsonStart...]).data(using: .utf8),
              let envelope = try JSONSerialization.jsonObject(with: inputData) as? [String: Any],
              let messages = envelope["messages"] as? [[String: Any]]
        else {
            throw URLError(.cannotParseResponse)
        }
        batchSizes.append(messages.count)

        return HTTPResponse(
            data: Data(#"{"choices":[{"message":{"content":null,"tool_calls":[{"type":"function","function":{"name":"submit_email_triage","arguments":"{\"results\":[]}"}}]}}]}"#.utf8),
            statusCode: 200,
            headers: [:]
        )
    }

    func recordedBatchSizes() -> [Int] {
        batchSizes
    }
}
