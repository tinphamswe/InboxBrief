import Foundation

struct ProxyEmailAnalyzer: EmailAnalyzing {
    private let transport: any HTTPTransport
    private let endpoint: URL
    private let codec: AIAnalysisCodec

    init(
        transport: any HTTPTransport,
        endpoint: URL,
        codec: AIAnalysisCodec = AIAnalysisCodec()
    ) {
        self.transport = transport
        self.endpoint = endpoint
        self.codec = codec
    }

    func analyze(
        _ messages: [EmailAnalysisInput],
        progress: @escaping @Sendable (OperationProgress) async -> Void
    ) async throws -> [EmailAssessment] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try codec.encodeInput(messages)
        } catch {
            throw EmailAnalysisFailure.invalidRequest
        }

        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw EmailAnalysisFailure.offline
        } catch {
            throw EmailAnalysisFailure.serviceUnavailable
        }

        switch response.statusCode {
        case 200..<300:
            break
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
        do {
            let assessments = try codec.decodeAnalysis(response.data)
            await progress(OperationProgress(completed: messages.count, total: messages.count))
            return assessments
        } catch {
            throw EmailAnalysisFailure.invalidResponse
        }
    }
}
