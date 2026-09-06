protocol OriginalMessageOpening: Sendable {
    @MainActor
    func open(_ target: OriginalMessageTarget) async -> Bool
}
