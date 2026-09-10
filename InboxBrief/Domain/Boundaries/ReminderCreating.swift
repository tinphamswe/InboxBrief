protocol ReminderCreating: Sendable {
    @MainActor
    func create(_ draft: ReminderDraft) async throws
}
