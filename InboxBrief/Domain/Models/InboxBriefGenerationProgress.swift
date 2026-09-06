struct OperationProgress: Equatable, Sendable {
    let completed: Int
    let total: Int

    init(completed: Int, total: Int) {
        let safeTotal = max(0, total)
        self.total = safeTotal
        self.completed = min(max(0, completed), safeTotal)
    }

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

enum InboxBriefGenerationProgress: Equatable, Sendable {
    case fetching(OperationProgress)
    case analyzing(OperationProgress)
}
