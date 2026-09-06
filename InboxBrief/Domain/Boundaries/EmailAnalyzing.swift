protocol EmailAnalyzing: Sendable {
    func analyze(
        _ messages: [EmailAnalysisInput],
        progress: @escaping @Sendable (OperationProgress) async -> Void
    ) async throws -> [EmailAssessment]
}

extension EmailAnalyzing {
    func analyze(_ messages: [EmailAnalysisInput]) async throws -> [EmailAssessment] {
        try await analyze(messages, progress: { _ in })
    }
}
