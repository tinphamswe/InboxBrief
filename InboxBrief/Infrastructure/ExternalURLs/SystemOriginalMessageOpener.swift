import UIKit

struct SystemOriginalMessageOpener: OriginalMessageOpening {
    @MainActor
    func open(_ target: OriginalMessageTarget) async -> Bool {
        if let searchQuery = target.searchQuery {
            UIPasteboard.general.string = searchQuery
        }
        return await UIApplication.shared.open(target.webURL)
    }
}
