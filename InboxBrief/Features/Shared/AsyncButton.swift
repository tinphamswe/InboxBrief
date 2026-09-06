import SwiftUI

struct AsyncButton<Label: View>: View {
    private let role: ButtonRole?
    private let action: @MainActor () async -> Void
    private let label: () -> Label

    @State private var requestID: UUID?

    init(
        role: ButtonRole? = nil,
        action: @escaping @MainActor () async -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.role = role
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(role: role) {
            requestID = UUID()
        } label: {
            label()
        }
        .task(id: requestID) {
            guard requestID != nil else { return }
            await action()
        }
    }
}
