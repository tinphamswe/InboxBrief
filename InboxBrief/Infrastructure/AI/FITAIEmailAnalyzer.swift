import Foundation

protocol RetrySleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct TaskRetrySleeper: RetrySleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

struct FITAIEmailAnalyzer: EmailAnalyzing {
    private let transport: any HTTPTransport
    private let endpoint: URL
    private let apiKey: String
    private let model: String
    private let batchSize: Int
    private let maximumConcurrentBatches: Int
    private let retryDelays: [Duration]
    private let retrySleeper: any RetrySleeping
    private let codec: AIAnalysisCodec

    init(
        transport: any HTTPTransport,
        endpoint: URL,
        apiKey: String,
        model: String,
        batchSize: Int = 8,
        maximumConcurrentBatches: Int = 8,
        retryDelays: [Duration] = [.milliseconds(500), .seconds(1)],
        retrySleeper: any RetrySleeping = TaskRetrySleeper(),
        codec: AIAnalysisCodec = AIAnalysisCodec()
    ) {
        self.transport = transport
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.batchSize = max(1, batchSize)
        self.maximumConcurrentBatches = max(1, maximumConcurrentBatches)
        self.retryDelays = retryDelays
        self.retrySleeper = retrySleeper
        self.codec = codec
    }

    func analyze(
        _ messages: [EmailAnalysisInput],
        progress: @escaping @Sendable (OperationProgress) async -> Void
    ) async throws -> [EmailAssessment] {
        guard !messages.isEmpty else { return [] }

        let batches = stride(from: 0, to: messages.count, by: batchSize).map { start in
            let end = min(start + batchSize, messages.count)
            return Array(messages[start..<end])
        }

        return try await withThrowingTaskGroup(
            of: (index: Int, assessments: [EmailAssessment]).self
        ) { group in
            var nextBatchIndex = 0
            let initialBatchCount = min(maximumConcurrentBatches, batches.count)

            while nextBatchIndex < initialBatchCount {
                let index = nextBatchIndex
                let batch = batches[index]
                group.addTask {
                    (index, try await analyzeBatch(batch))
                }
                nextBatchIndex += 1
            }

            var completed: [(index: Int, assessments: [EmailAssessment])] = []
            var completedMessageCount = 0
            while let result = try await group.next() {
                completed.append(result)
                completedMessageCount += batches[result.index].count
                await progress(OperationProgress(
                    completed: completedMessageCount,
                    total: messages.count
                ))

                if nextBatchIndex < batches.count {
                    let index = nextBatchIndex
                    let batch = batches[index]
                    group.addTask {
                        (index, try await analyzeBatch(batch))
                    }
                    nextBatchIndex += 1
                }
            }

            return completed
                .sorted { $0.index < $1.index }
                .flatMap(\.assessments)
        }
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
            "messages": [
                ["role": "system", "content": EmailTriagePrompt.system],
                ["role": "user", "content": "Untrusted email data follows as JSON:\n\(input)"],
            ],
            "tools": [[
                "type": "function",
                "function": [
                    "name": "submit_email_triage",
                    "description": "Submit one structured triage result for every supplied email.",
                    "parameters": AIAnalysisCodec.outputSchema,
                ],
            ]],
            "tool_choice": [
                "type": "function",
                "function": ["name": "submit_email_triage"],
            ],
            "temperature": 0,
            "max_tokens": 2_000,
            "stream": false,
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let response = try await sendWithBackoff(request)
        try validate(response.statusCode)
        do {
            return try codec.decodeFITAIResponse(response.data)
        } catch let failure as EmailAnalysisFailure {
            throw failure
        } catch {
            throw EmailAnalysisFailure.invalidResponse
        }
    }

    private func sendWithBackoff(_ request: URLRequest) async throws -> HTTPResponse {
        for delay in retryDelays {
            let response = try await send(request)
            guard response.statusCode == 429 else { return response }
            try await retrySleeper.sleep(for: delay)
        }
        return try await send(request)
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
