//
//  InboxBriefApp.swift
//  InboxBrief
//
//  Created by Tin Pham on 5/9/26.
//

import SwiftUI

@main
struct InboxBriefApp: App {
    private let container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            ContentView(
                briefingViewModel: container.briefingViewModel,
                accountsViewModel: container.accountsViewModel
            )
        }
    }
}
