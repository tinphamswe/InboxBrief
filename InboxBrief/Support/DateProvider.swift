import Foundation

struct DateProvider: Sendable {
    private let value: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date) {
        value = now
    }

    func now() -> Date {
        value()
    }

    static let live = DateProvider(now: Date.init)
}
